#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Strategy: 4× RTX 4090 (48 GB) — Qwen3 RAG 全套一键启动
# =============================================================================
#
# 本文件是「环境组合策略」，按固定槽位/端口编排各模块启动器。
# 各模块的实际启动、冒烟测试、Replace 逻辑仍在 scripts/ 下独立完成：
#
#   scripts/qwen3.8-27b-fp8/sglang-qwen3.8-27b-fp8   — LLM
#   scripts/qwen3-embedding/sglang-qwen3-embedding   — Embedding
#   scripts/qwen3-reranker/sglang-qwen3-reranker     — Reranker
#
# 槽位 = CUDA 设备索引（cuda:N）。GPU 编号 = 槽位 + 1。
# 端口策略：LLM 1xxxx · Embedding 2xxxx · Reranker 3xxxx
#
# ┌────────┬──────────────────────────────────────┬───────┬──────────┐
# │ 槽位   │ 服务                                 │ 端口  │ mem-frac │
# ├────────┼──────────────────────────────────────┼───────┼──────────┤
# │ cuda:0 │ LLM  Qwen3.8-27B-FP8                 │ 10000 │ 0.85     │
# │ cuda:1 │ Embedding  Qwen3-Embedding-8B        │ 20001 │ 0.45     │
# │ cuda:2 │ Reranker   Qwen3-Reranker-8B         │ 30001 │ 0.48     │
# │ cuda:3 │ Embedding  Qwen3-Embedding-4B        │ 20002 │ 0.21     │
# │        │ Reranker   Qwen3-Reranker-4B（同卡） │ 30002 │ 0.24     │
# └────────┴──────────────────────────────────────┴───────┴──────────┘
#
# 启动策略：Wave 1 四卡并行（cuda:0/1/2/3 各一服务），Wave 2 串行 Reranker 4B（cuda:3 同卡）。
# 总耗时 ≈ 最慢单服务 + Reranker 4B，而非五步相加。
#
# 每次启动完成后会删除旧手册，并生成本目录 maas_description_<YYMMDD-HHMMSS>.md。
#
# Usage:
#   ./strategy/4x4090-48g-rag-suite/4x4090-48g-rag-suite.sh
#   SKIP_SMOKE_TEST=1 ./strategy/4x4090-48g-rag-suite/4x4090-48g-rag-suite.sh
#   SERVICE_HOST=<ip> ./strategy/4x4090-48g-rag-suite/4x4090-48g-rag-suite.sh  # 强制指定手册地址
#
# 手册对外地址自动探测（未设 SERVICE_HOST）：Tailscale 100.x → 局域网 → 127.0.0.1
#
# 仅重生成手册（不重启）:
#   bash -c 'source strategy/4x4090-48g-rag-suite/4x4090-48g-rag-suite.sh; write_maas_description'
#
# 首次部署请先运行: ./scripts/qwen3.8-27b-fp8/sglang-install
# =============================================================================

STRATEGY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${STRATEGY_DIR}/../.." && pwd)"
DATA_ROOT="${DATA_ROOT:-/data/edwardluke}"
SGLANG_CACHE_DIR="${SGLANG_CACHE_DIR:-${DATA_ROOT}/cache/sglang}"

LLM="${REPO_ROOT}/scripts/qwen3.8-27b-fp8/sglang-qwen3.8-27b-fp8"
EMB="${REPO_ROOT}/scripts/qwen3-embedding/sglang-qwen3-embedding"
RER="${REPO_ROOT}/scripts/qwen3-reranker/sglang-qwen3-reranker"

step() {
  printf '\n==> %s\n' "$*"
}

LAUNCH_PIDS=()
LAUNCH_TAGS=()
LAUNCH_LOGS=()

start_service_bg() {
  local tag="$1"
  shift
  local log="${SGLANG_CACHE_DIR}/launch-${tag}.log"
  printf '    · %s\n' "${tag}"
  (
    set -euo pipefail
    "$@"
  ) >"${log}" 2>&1 &
  LAUNCH_PIDS+=($!)
  LAUNCH_TAGS+=("${tag}")
  LAUNCH_LOGS+=("${log}")
}

wait_all_launches() {
  local failed=0 i
  for i in "${!LAUNCH_PIDS[@]}"; do
    if wait "${LAUNCH_PIDS[$i]}"; then
      printf '  OK  %s\n' "${LAUNCH_TAGS[$i]}"
    else
      echo "ERROR: ${LAUNCH_TAGS[$i]} failed — see ${LAUNCH_LOGS[$i]}" >&2
      tail -30 "${LAUNCH_LOGS[$i]}" >&2
      failed=1
    fi
  done
  LAUNCH_PIDS=()
  LAUNCH_TAGS=()
  LAUNCH_LOGS=()
  if (( failed != 0 )); then
    exit 1
  fi
}

wait_all_health() {
  local port elapsed
  for port in 10000 20001 20002 30001 30002; do
    elapsed=0
    while (( elapsed < 600 )); do
      if curl -sf "http://127.0.0.1:${port}/health" >/dev/null 2>&1; then
        break
      fi
      sleep 2
      elapsed=$((elapsed + 2))
    done
    if (( elapsed >= 600 )); then
      echo "ERROR: /health timeout on port ${port}" >&2
      exit 1
    fi
  done
}

smoke_with_retry() {
  local label="$1" attempts="$2"
  shift 2
  local i
  for (( i = 1; i <= attempts; i++ )); do
    if "$@"; then
      printf '  OK  %s\n' "${label}"
      return 0
    fi
    if (( i < attempts )); then
      printf '  retry %s (%d/%d)...\n' "${label}" "${i}" "${attempts}"
      sleep 15
    fi
  done
  echo "ERROR: smoke test failed — ${label}" >&2
  return 1
}

run_suite_smoke_tests() {
  [[ "${SKIP_SMOKE_TEST:-0}" == "1" ]] && return 0

  local python="${PYTHON:-${DATA_ROOT}/venvs/sglang/bin/python}"
  # shellcheck source=scripts/qwen3.8-27b-fp8/lib/smoke-tests.sh
  source "${REPO_ROOT}/scripts/qwen3.8-27b-fp8/lib/smoke-tests.sh"
  resolve_model_paths

  step "Smoke tests (suite-wide, sequential)"
  wait_all_health

  smoke_with_retry "LLM /v1/chat/completions" 3 \
    smoke_test_llm "127.0.0.1" 10000 "${MODEL_LLM}" "${python}" || exit 1
  smoke_with_retry "Embedding 8B /v1/embeddings" 2 \
    smoke_test_embedding "127.0.0.1" 20001 "${MODEL_EMB8}" 4096 "${python}" || exit 1
  smoke_with_retry "Embedding 4B /v1/embeddings" 2 \
    smoke_test_embedding "127.0.0.1" 20002 "${MODEL_EMB4}" 2560 "${python}" || exit 1
  smoke_with_retry "Reranker 8B /v1/rerank" 2 \
    smoke_test_reranker "127.0.0.1" 30001 "${MODEL_RER8}" "${python}" || exit 1
  smoke_with_retry "Reranker 4B /v1/rerank" 2 \
    smoke_test_reranker "127.0.0.1" 30002 "${MODEL_RER4}" "${python}" || exit 1
}

MAAS_PUBLIC_HOST=""
MAAS_LAN_HOST=""

is_loopback_ip() {
  [[ "${1}" =~ ^127\. ]]
}

is_docker_bridge_ip() {
  [[ "${1}" =~ ^172\.(1[7-9]|2[0-9]|3[0-1])\. ]]
}

is_tailscale_ip() {
  # Tailscale CGNAT range 100.64.0.0/10
  [[ "${1}" =~ ^100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\. ]]
}

is_private_lan_ip() {
  [[ "${1}" =~ ^10\. ]] \
    || [[ "${1}" =~ ^192\.168\. ]] \
    || [[ "${1}" =~ ^172\.(1[0-9]|2[0-9]|3[0-1])\. ]]
}

probe_host_health() {
  local host="${1}" port="${2:-10000}"
  curl -sf --connect-timeout 2 "http://${host}:${port}/health" >/dev/null 2>&1
}

collect_host_candidates() {
  local -a seen=() ip already=""
  _add_host_candidate() {
    ip="${1}"
    [[ -z "${ip}" ]] && return 0
    is_loopback_ip "${ip}" && return 0
    is_docker_bridge_ip "${ip}" && return 0
    [[ "${ip}" == *:* ]] && return 0
    for already in "${seen[@]}"; do
      [[ "${already}" == "${ip}" ]] && return 0
    done
    seen+=("${ip}")
    printf '%s\n' "${ip}"
  }

  if command -v tailscale >/dev/null 2>&1; then
    _add_host_candidate "$(tailscale ip -4 2>/dev/null || true)"
  fi
  for ip in $(hostname -I 2>/dev/null || true); do
    _add_host_candidate "${ip}"
  done
}

resolve_service_hosts() {
  MAAS_PUBLIC_HOST=""
  MAAS_LAN_HOST=""

  if [[ -n "${SERVICE_HOST:-}" ]]; then
    MAAS_PUBLIC_HOST="${SERVICE_HOST}"
    return 0
  fi

  local ip reachable_ts="" reachable_lan="" fallback_ts="" fallback_lan=""
  while IFS= read -r ip; do
    [[ -z "${ip}" ]] && continue
    if is_tailscale_ip "${ip}"; then
      [[ -z "${fallback_ts}" ]] && fallback_ts="${ip}"
      if [[ -z "${reachable_ts}" ]] && probe_host_health "${ip}"; then
        reachable_ts="${ip}"
      fi
    elif is_private_lan_ip "${ip}" && ! is_docker_bridge_ip "${ip}"; then
      [[ -z "${fallback_lan}" ]] && fallback_lan="${ip}"
      if [[ -z "${reachable_lan}" ]] && probe_host_health "${ip}"; then
        reachable_lan="${ip}"
      fi
    fi
  done < <(collect_host_candidates)

  if [[ -n "${reachable_ts}" ]]; then
    MAAS_PUBLIC_HOST="${reachable_ts}"
    MAAS_LAN_HOST="${reachable_lan:-${fallback_lan}}"
  elif [[ -n "${reachable_lan}" ]]; then
    MAAS_PUBLIC_HOST="${reachable_lan}"
  elif [[ -n "${fallback_ts}" ]]; then
    MAAS_PUBLIC_HOST="${fallback_ts}"
    MAAS_LAN_HOST="${fallback_lan}"
  elif [[ -n "${fallback_lan}" ]]; then
    MAAS_PUBLIC_HOST="${fallback_lan}"
  else
    MAAS_PUBLIC_HOST="127.0.0.1"
  fi

  if [[ "${MAAS_LAN_HOST}" == "${MAAS_PUBLIC_HOST}" ]]; then
    MAAS_LAN_HOST=""
  fi
}

detect_service_host() {
  resolve_service_hosts
  printf '%s' "${MAAS_PUBLIC_HOST}"
}

resolve_model_paths() {
  MODEL_LLM="/data/models/Qwen3.8-27B-FP8"
  MODEL_EMB8="/data/models/Qwen3-Embedding-8B"
  MODEL_EMB4="/data/models/Qwen3-Embedding-4B"
  if [[ -d /data/models/Qwen3-Reranker-8B ]]; then
    MODEL_RER8="/data/models/Qwen3-Reranker-8B"
  else
    MODEL_RER8="/data/models/Qwen3-Reranker-8"
  fi
  MODEL_RER4="/data/models/Qwen3-Reranker-4B"
}

purge_old_maas_descriptions() {
  local old
  shopt -s nullglob
  for old in "${STRATEGY_DIR}"/maas_description_*.md; do
    rm -f "${old}"
  done
  shopt -u nullglob
}

write_maas_description() {
  local host lan_host ts outfile host_detect_note internal_addrs
  resolve_model_paths
  resolve_service_hosts
  host="${MAAS_PUBLIC_HOST}"
  lan_host="${MAAS_LAN_HOST}"
  purge_old_maas_descriptions
  ts="$(date '+%y%m%d-%H%M%S')"
  outfile="${STRATEGY_DIR}/maas_description_${ts}.md"

  if [[ -n "${SERVICE_HOST:-}" ]]; then
    host_detect_note="手动指定 \`SERVICE_HOST\`"
  elif is_tailscale_ip "${host}"; then
    host_detect_note="Tailscale 自动探测"
  elif [[ "${host}" != "127.0.0.1" ]]; then
    host_detect_note="局域网自动探测"
  else
    host_detect_note="未探测到跨网段地址"
  fi

  internal_addrs="\`127.0.0.1\`"
  if [[ -n "${lan_host}" ]]; then
    internal_addrs="${internal_addrs}、\`${lan_host}\`"
  fi

  cat >"${outfile}" <<EOF
# Qwen3 RAG MaaS 接入手册

> 自动生成于 $(date '+%Y-%m-%d %H:%M:%S %z')  
> 策略目录: \`${STRATEGY_DIR}\`  
> **对外服务地址: ${host}**（${host_detect_note}；仅限局域网/本地调试：${internal_addrs}）

本文档供其它项目/单位快速接入本机部署的 Qwen3 RAG 推理服务。所有接口均为 **OpenAI 兼容** REST API（SGLang 后端），无需 API Key。跨单位接入请使用上方**对外服务地址**及下文 URL，勿使用括号内地址。

---

## 1. 服务与端口一览

| 组件 | 型号 | GPU (cuda) | 端口 | mem-frac | 向量维度 | Health | API |
|------|------|------------|------|----------|----------|--------|-----|
| LLM | Qwen3.8-27B-FP8 | 0 | **10000** | 0.85 | — | \`/health\` | \`/v1/chat/completions\` |
| Embedding | Qwen3-Embedding-8B | 1 | **20001** | 0.45 | 4096 | \`/health\` | \`/v1/embeddings\` |
| Reranker | Qwen3-Reranker-8B | 2 | **30001** | 0.48 | — | \`/health\` | \`/v1/rerank\` |
| Embedding | Qwen3-Embedding-4B | 3 | **20002** | 0.21 | 2560 | \`/health\` | \`/v1/embeddings\` |
| Reranker | Qwen3-Reranker-4B | 3 | **30002** | 0.24 | — | \`/health\` | \`/v1/rerank\` |

**端口规则:** LLM \`1xxxx\` · Embedding \`2xxxx\` · Reranker \`3xxxx\`

---

## 2. 模型与官方地址

请求体中的 \`model\` 字段须使用下表 **服务端 model ID**（本地权重路径），与 HuggingFace 仓库名不同。

| 组件 | 服务端 model ID | HuggingFace 官方 |
|------|-----------------|------------------|
| LLM | \`${MODEL_LLM}\` | [Qwen/Qwen3.8-27B-FP8](https://huggingface.co/Qwen/Qwen3.8-27B-FP8) |
| Embedding 8B | \`${MODEL_EMB8}\` | [Qwen/Qwen3-Embedding-8B](https://huggingface.co/Qwen/Qwen3-Embedding-8B) |
| Embedding 4B | \`${MODEL_EMB4}\` | [Qwen/Qwen3-Embedding-4B](https://huggingface.co/Qwen/Qwen3-Embedding-4B) |
| Reranker 8B | \`${MODEL_RER8}\` | [Qwen/Qwen3-Reranker-8B](https://huggingface.co/Qwen/Qwen3-Reranker-8B) |
| Reranker 4B | \`${MODEL_RER4}\` | [Qwen/Qwen3-Reranker-4B](https://huggingface.co/Qwen/Qwen3-Reranker-4B) |

---

## 3. 环境变量（复制到其他项目）

\`\`\`bash
# --- LLM ---
LLM_BASE_URL=http://${host}:10000/v1
LLM_MODEL=${MODEL_LLM}
LLM_HEALTH=http://${host}:10000/health

# --- Embedding 8B（高质量 RAG，4096 维）---
EMBEDDING_8B_BASE_URL=http://${host}:20001/v1
EMBEDDING_8B_MODEL=${MODEL_EMB8}
EMBEDDING_8B_DIM=4096

# --- Embedding 4B（轻量，2560 维）---
EMBEDDING_4B_BASE_URL=http://${host}:20002/v1
EMBEDDING_4B_MODEL=${MODEL_EMB4}
EMBEDDING_4B_DIM=2560

# --- Reranker 8B ---
RERANKER_8B_BASE_URL=http://${host}:30001/v1
RERANKER_8B_MODEL=${MODEL_RER8}

# --- Reranker 4B ---
RERANKER_4B_BASE_URL=http://${host}:30002/v1
RERANKER_4B_MODEL=${MODEL_RER4}
\`\`\`

---

## 4. 健康检查

\`\`\`bash
curl http://${host}:10000/health
curl http://${host}:20001/health
curl http://${host}:20002/health
curl http://${host}:30001/health
curl http://${host}:30002/health
\`\`\`

返回 \`200\` 且 body 含 \`healthy\` 即表示就绪。

---

## 5. API 调用示例

### 5.1 LLM 对话 — \`POST /v1/chat/completions\`

\`\`\`bash
curl http://${host}:10000/v1/chat/completions \\
  -H "Content-Type: application/json" \\
  -d '{
    "model": "${MODEL_LLM}",
    "messages": [{"role": "user", "content": "你好，请用一句话介绍你自己。"}],
    "max_tokens": 128,
    "temperature": 0.7
  }'
\`\`\`

**Python（OpenAI SDK）:**

\`\`\`python
from openai import OpenAI

client = OpenAI(base_url="http://${host}:10000/v1", api_key="unused")
resp = client.chat.completions.create(
    model="${MODEL_LLM}",
    messages=[{"role": "user", "content": "你好"}],
    max_tokens=128,
)
print(resp.choices[0].message.content)
\`\`\`

---

### 5.2 文本向量 — \`POST /v1/embeddings\`

**8B（4096 维，端口 20001）:**

\`\`\`bash
curl http://${host}:20001/v1/embeddings \\
  -H "Content-Type: application/json" \\
  -d '{
    "model": "${MODEL_EMB8}",
    "input": "Qwen3-Embedding-8B 用于语义检索"
  }'
\`\`\`

**4B（2560 维，端口 20002）:**

\`\`\`bash
curl http://${host}:20002/v1/embeddings \\
  -H "Content-Type: application/json" \\
  -d '{
    "model": "${MODEL_EMB4}",
    "input": "Qwen3-Embedding-4B 轻量向量模型"
  }'
\`\`\`

**Python:**

\`\`\`python
from openai import OpenAI

emb = OpenAI(base_url="http://${host}:20001/v1", api_key="unused")
vec = emb.embeddings.create(
    model="${MODEL_EMB8}",
    input="待检索的文档片段",
).data[0].embedding
print(len(vec))  # 4096
\`\`\`

---

### 5.3 重排序 — \`POST /v1/rerank\`

**简单案例（8B，端口 30001）:**

\`\`\`bash
curl http://${host}:30001/v1/rerank \\
  -H "Content-Type: application/json" \\
  -d '{
    "model": "${MODEL_RER8}",
    "query": "What is Python?",
    "documents": [
      "Python is a programming language.",
      "The sky is blue."
    ]
  }'
\`\`\`

**RAG 语义案例（验证 8B reranker 能区分相关文档）:**

\`\`\`bash
curl http://${host}:30001/v1/rerank \\
  -H "Content-Type: application/json" \\
  -d '{
    "model": "${MODEL_RER8}",
    "query": "Qwen embedding model with 4096 dimensions?",
    "documents": [
      "Qwen3-Embedding-8B produces 4096-dimensional vectors for semantic retrieval tasks.",
      "Qwen3-Embedding-4B produces 2560-dimensional vectors and is faster than the 8B variant.",
      "OpenAI text-embedding-3-large maps text to high-dimensional vectors for search."
    ]
  }'
\`\`\`

返回为 \`[{"index": 0, "score": ...}, ...]\`，按 \`score\` 降序即为重排结果。4B reranker 将 \`30001\` 换为 \`30002\`，\`model\` 换为 \`${MODEL_RER4}\`。

---

## 6. RAG 接入建议

| 场景 | Embedding | Reranker | 说明 |
|------|-----------|----------|------|
| **高质量（推荐）** | :20001 8B (4096d) | :30001 8B | 精度优先 |
| **轻量 / 省显存** | :20002 4B (2560d) | :30002 4B | 两服务同卡 cuda:3 |

**典型 RAG 流程:**

1. 用 Embedding 服务将 query 与候选文档转为向量，做 Top-K 召回（Milvus / FAISS / pgvector 等）。
2. 将 query + Top-K 文档送入 Reranker，按 score 重排，取 Top-N 作为上下文。
3. 将重排后的上下文 + 用户问题送入 LLM（:10000）生成答案。

**注意:** Embedding 8B 与 4B 向量维度不同，索引库须与所选 Embedding 服务一致，不可混用。

---

## 7. 完整 RAG 最小示例（curl 串联）

\`\`\`bash
HOST=${host}

# Step 1: 对 query 做 embedding
curl -s "http://\${HOST}:20001/v1/embeddings" \\
  -H "Content-Type: application/json" \\
  -d '{"model":"${MODEL_EMB8}","input":"什么是 RAG？"}' \\
  | jq '.data[0].embedding | length'   # 应输出 4096

# Step 2: 对召回候选做 rerank（此处直接传入 3 段文本模拟召回结果）
curl -s "http://\${HOST}:30001/v1/rerank" \\
  -H "Content-Type: application/json" \\
  -d '{
    "model":"${MODEL_RER8}",
    "query":"什么是 RAG？",
    "documents":[
      "RAG（Retrieval-Augmented Generation）通过检索外部知识增强大模型回答。",
      "Python 是一种解释型编程语言。",
      "向量数据库用于存储 embedding 并做相似度搜索。"
    ]
  }' | jq 'sort_by(-.score)'

# Step 3: 将最相关上下文送入 LLM
curl -s "http://\${HOST}:10000/v1/chat/completions" \\
  -H "Content-Type: application/json" \\
  -d '{
    "model":"${MODEL_LLM}",
    "messages":[
      {"role":"system","content":"根据给定上下文回答。上下文：RAG（Retrieval-Augmented Generation）通过检索外部知识增强大模型回答。"},
      {"role":"user","content":"什么是 RAG？"}
    ],
    "max_tokens":256
  }' | jq -r '.choices[0].message.content'
\`\`\`

---

## 8. 运维信息

| 项目 | 值 |
|------|-----|
| 一键启动脚本 | \`${STRATEGY_DIR}/4x4090-48g-rag-suite.sh\` |
| 启动策略 | Wave 1 四卡并行 → Wave 2 Reranker 4B 串行（cuda:3 同卡） |
| 对外地址 | 默认自动探测（Tailscale \`100.x\` 优先）；可 \`SERVICE_HOST=<ip>\` 覆盖 |
| 跳过冒烟测试 | \`SKIP_SMOKE_TEST=1 ./strategy/4x4090-48g-rag-suite/4x4090-48g-rag-suite.sh\` |
| 并行启动日志 | \`${SGLANG_CACHE_DIR}/launch-{llm,embedding-8b,embedding-4b,reranker-8b}.log\` |
| LLM 日志 | \`${SGLANG_CACHE_DIR}/sglang-llm.log\` |
| Embedding 8B 日志 | \`${SGLANG_CACHE_DIR}/sglang-embedding-8b.log\` |
| Embedding 4B 日志 | \`${SGLANG_CACHE_DIR}/sglang-embedding-4b.log\` |
| Reranker 8B 日志 | \`${SGLANG_CACHE_DIR}/sglang-reranker-8b.log\` |
| Reranker 4B 日志 | \`${SGLANG_CACHE_DIR}/sglang-reranker-4b.log\` |

每次重新运行启动脚本会替换同端口旧实例，删除旧手册并**重新生成本手册**。

---

## 9. 常见问题

| 问题 | 处理 |
|------|------|
| 连接超时 | 确认防火墙放行 10000/20001/20002/30001/30002；跨网段时使用 \`SERVICE_HOST\` 指定的可达 IP |
| \`/health\` 503 | 首次启动需 1–3 分钟（含 CUDA graph capture），查看对应日志 |
| Reranker 分数全部相同 | 服务端 chat template 配置问题，联系运维；正常时 hard case 最高分应 > 0.1 |
| Embedding 维度不符 | 8B→4096，4B→2560；检查是否连错端口 |
| \`model\` 字段报错 | 必须使用本文「服务端 model ID」列的路径，不能用 HF 短名 |

EOF

  printf '%s\n' "${outfile}"
}

print_service_manifest() {
  local outfile
  resolve_service_hosts
  outfile="$(write_maas_description)"
  cat <<EOF

==============================================================================
  RAG Suite 已就绪
  对外服务地址: ${MAAS_PUBLIC_HOST}$([[ -n "${MAAS_LAN_HOST}" ]] && printf '  ·  局域网: %s' "${MAAS_LAN_HOST}")
  接入手册: ${outfile}
==============================================================================

EOF
}

main() {
  step "Wave 1/2  并行启动 4 服务 (cuda:0 LLM · cuda:1 Emb8B · cuda:2 Rer8B · cuda:3 Emb4B)"
  start_service_bg "llm" \
    env LOG_FILE="${SGLANG_CACHE_DIR}/sglang-llm.log" SKIP_SMOKE_TEST=1 \
    "${LLM}" -slot=0 -port=10000 -tp=1 -dp=1 -y
  start_service_bg "embedding-8b" \
    env LOG_FILE="${SGLANG_CACHE_DIR}/sglang-embedding-8b.log" SKIP_SMOKE_TEST=1 \
    "${EMB}" -size=8b -slot=1 -port=20001 -mem=0.45 -y
  start_service_bg "reranker-8b" \
    env LOG_FILE="${SGLANG_CACHE_DIR}/sglang-reranker-8b.log" SKIP_SMOKE_TEST=1 \
    "${RER}" -size=8b -slot=2 -port=30001 -mem=0.48 -y
  start_service_bg "embedding-4b" \
    env LOG_FILE="${SGLANG_CACHE_DIR}/sglang-embedding-4b.log" SKIP_SMOKE_TEST=1 \
    "${EMB}" -size=4b -slot=3 -port=20002 -mem=0.21 -y
  wait_all_launches

  step "Wave 2/2  Reranker 4B  (cuda:3, port 30002 — 与 Emb4B 同卡，须等 Wave 1 完成)"
  SKIP_SMOKE_TEST=1 LOG_FILE="${SGLANG_CACHE_DIR}/sglang-reranker-4b.log" \
    "${RER}" -size=4b -slot=3 -port=30002 -mem=0.24 -y

  run_suite_smoke_tests
  print_service_manifest
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
