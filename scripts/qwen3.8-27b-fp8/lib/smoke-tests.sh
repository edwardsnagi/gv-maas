#!/usr/bin/env bash
# Post-launch smoke tests for SGLang MaaS services.
# Source from launch scripts after /health is ready.

smoke_server_alive() {
  kill -0 "${1}" 2>/dev/null
}

smoke_curl_json() {
  local url="${1}" data="${2}" out="${3}"
  curl -sfS "${url}" \
    -H "Content-Type: application/json" \
    -d "${data}" \
    -o "${out}"
}

smoke_run() {
  local label="${1}" pid="${2}" log_file="${3:-/dev/null}"
  shift 3
  echo ""
  echo "Smoke test: ${label}..."
  if ! smoke_server_alive "${pid}"; then
    echo "ERROR: server PID ${pid} exited before smoke test." >&2
    [[ -f "${log_file}" ]] && tail -30 "${log_file}" >&2
    return 1
  fi
  if "$@"; then
    echo "  OK  ${label}"
    return 0
  fi
  echo "ERROR: smoke test failed — ${label}" >&2
  [[ -f "${log_file}" ]] && tail -30 "${log_file}" >&2
  return 1
}

# LLM: /v1/chat/completions (official starter flow)
smoke_test_llm() {
  local host="${1}" port="${2}" model_path="${3}" python="${4:-python3}"
  local tmp rc=0
  tmp="$(mktemp)"

  if ! smoke_curl_json \
    "http://${host}:${port}/v1/chat/completions" \
    "{\"model\":\"${model_path}\",\"messages\":[{\"role\":\"user\",\"content\":\"你好\"}],\"max_tokens\":64}" \
    "${tmp}"; then
    echo "  chat/completions request failed" >&2
    rc=1
  elif ! "${python}" - "${tmp}" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
choices = data.get("choices") or []
if not choices:
    raise SystemExit("no choices in response")
content = (choices[0].get("message") or {}).get("content") or ""
if not str(content).strip():
    raise SystemExit("empty assistant content")
print(f"  reply: {str(content).strip()[:80]!r}")
PY
  then
    rc=1
  fi

  rm -f "${tmp}"
  return "${rc}"
}

# Embedding: /v1/embeddings + vector dimension check
smoke_test_embedding() {
  local host="${1}" port="${2}" model_path="${3}" expected_dim="${4}" python="${5:-python3}"
  local tmp rc=0
  tmp="$(mktemp)"

  if ! smoke_curl_json \
    "http://${host}:${port}/v1/embeddings" \
    "{\"model\":\"${model_path}\",\"input\":\"你好\"}" \
    "${tmp}"; then
    echo "  embeddings request failed" >&2
    rc=1
  elif ! "${python}" - "${tmp}" "${expected_dim}" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
expected = int(sys.argv[2])
items = data.get("data") or []
if not items:
    raise SystemExit("no embedding data in response")
emb = items[0].get("embedding") or []
if len(emb) != expected:
    raise SystemExit(f"expected dim {expected}, got {len(emb)}")
print(f"  vector dim: {len(emb)}")
PY
  then
    rc=1
  fi

  rm -f "${tmp}"
  return "${rc}"
}

# Reranker: /v1/rerank — easy + hard queries; 8B must exceed score floor on hard case
smoke_test_reranker() {
  local host="${1}" port="${2}" model_path="${3}" python="${4:-python3}"
  smoke_rerank_case "${host}" "${port}" "${model_path}" "${python}" \
    "What is Python?" \
    '["Python is a programming language.","The sky is blue."]' \
    0 0.0 || return 1
  smoke_rerank_hard_case "${host}" "${port}" "${model_path}" "${python}" || return 1
}

smoke_rerank_hard_case() {
  local host="${1}" port="${2}" model_path="${3}" python="${4:-python3}" tmp payload
  tmp="$(mktemp)"
  payload="$(MODEL="${model_path}" "${python}" - <<'PY'
import json, os
print(json.dumps({
    "model": os.environ["MODEL"],
    "query": "Qwen embedding model with 4096 dimensions?",
    "documents": [
        "Qwen3-Embedding-8B produces 4096-dimensional vectors for semantic retrieval tasks.",
        "Qwen3-Embedding-4B produces 2560-dimensional vectors and is faster than the 8B variant.",
        "OpenAI text-embedding-3-large maps text to high-dimensional vectors for search.",
    ],
}))
PY
)"
  if ! smoke_curl_json "http://${host}:${port}/v1/rerank" "${payload}" "${tmp}"; then
    rm -f "${tmp}"
    echo "  hard rerank request failed" >&2
    return 1
  fi
  if ! "${python}" - "${tmp}" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
scores = {int(x["index"]): float(x["score"]) for x in data}
if len(set(scores.values())) == 1:
    raise SystemExit("identical scores on hard case")
if scores.get(0, 0) <= scores.get(2, 0):
    raise SystemExit(f"4096-dim doc should beat irrelevant doc: {scores}")
if max(scores.values()) < 0.1:
    raise SystemExit(f"scores too low — likely broken template: {scores}")
ranked = sorted(scores.items(), key=lambda x: x[1], reverse=True)
print(f"  hard case order: {ranked}")
PY
  then
    rm -f "${tmp}"
    return 1
  fi
  rm -f "${tmp}"
}

smoke_rerank_case() {
  local host="${1}" port="${2}" model_path="${3}" python="${4}" query="${5}" docs_json="${6}"
  local expect_index="${7}" min_top_score="${8}" tmp payload rc=0
  tmp="$(mktemp)"
  payload="$(MODEL="${model_path}" QUERY="${query}" DOCS="${docs_json}" "${python}" - <<'PY'
import json, os
print(json.dumps({
    "model": os.environ["MODEL"],
    "query": os.environ["QUERY"],
    "documents": json.loads(os.environ["DOCS"]),
}))
PY
)"
  if ! smoke_curl_json \
    "http://${host}:${port}/v1/rerank" \
    "${payload}" \
    "${tmp}"; then
    rm -f "${tmp}"
    echo "  rerank request failed" >&2
    return 1
  fi

  if "${python}" - "${tmp}" "${expect_index}" "${min_top_score}" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
expect_index = int(sys.argv[2])
min_top = float(sys.argv[3])
if not isinstance(data, list) or len(data) < 2:
    raise SystemExit(f"expected >=2 rerank results, got {data!r}")
scores = {int(item["index"]): float(item["score"]) for item in data}
if len(set(scores.values())) == 1:
    raise SystemExit("identical scores — chat template or lm_head may be misconfigured")
ranked = sorted(scores.items(), key=lambda x: x[1], reverse=True)
top_index, top_score = ranked[0]
if top_index != expect_index:
    raise SystemExit(
        f"expected doc {expect_index} first, got order {ranked}"
    )
if top_score < min_top:
    raise SystemExit(
        f"top score {top_score:.4f} below floor {min_top} — scoring likely broken"
    )
spread = ranked[0][1] - ranked[-1][1]
print(f"  top doc={top_index} score={top_score:.4f} spread={spread:.4f}")
PY
  then
    :
  else
    rc=1
  fi
  rm -f "${tmp}"
  return "${rc}"
}

smoke_expected_embedding_dim() {
  case "${1}" in
    4b) printf '2560' ;;
    8b) printf '4096' ;;
    *) printf '4096' ;;
  esac
}
