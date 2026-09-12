#!/usr/bin/env bash
# Embedding launch wizard (3 steps: size → slot → port).
# Requires: interactive.sh already sourced.

EMBED_MODEL_SIZE="${EMBED_MODEL_SIZE:-8b}"

resolve_embedding_paths() {
  EMBED_MODEL_SIZE="$(printf '%s' "${EMBED_MODEL_SIZE}" | tr '[:upper:]' '[:lower:]')"
  case "${EMBED_MODEL_SIZE}" in
    4b)
      MODEL_PATH="${MODEL_PATH:-/data/models/Qwen3-Embedding-4B}"
      MODEL_NAME="Qwen3-Embedding-4B"
      ;;
    8b)
      MODEL_PATH="${MODEL_PATH:-/data/models/Qwen3-Embedding-8B}"
      MODEL_NAME="Qwen3-Embedding-8B"
      ;;
    *)
      printf '  %s%s invalid size: %s (use 4b or 8b)%s\n' "${CR}" "${G_FAIL}" "${EMBED_MODEL_SIZE}" "${C0}" >&2
      return 1
      ;;
  esac
}

wizard_step_embedding_size() {
  local choice default="1"
  WIZ_MODEL="Qwen3 Embedding"
  WIZ_HINT="Step 1 ${G_SEP} Model size"
  ui_step_intro 1 3 "${WIZ_MODEL}" "${WIZ_HINT}"

  ui_rule
  printf '  %sSelect embedding model:%s\n\n' "${CB}" "${C0}"

  ui_menu_pick "Choice" "${default}" \
    "[1] ${G_STAR} 8B  ${G_DASH}  /data/models/Qwen3-Embedding-8B  (default)" \
    "[2]   4B  ${G_DASH}  /data/models/Qwen3-Embedding-4B  (lower VRAM, faster)"
  choice="${UI_CHOICE}"

  case "${choice}" in
    1|"") EMBED_MODEL_SIZE="8b" ;;
    2) EMBED_MODEL_SIZE="4b" ;;
    *)
      printf '  %s%s invalid choice%s\n' "${CR}" "${G_FAIL}" "${C0}" >&2
      return 1
      ;;
  esac

  resolve_embedding_paths || return 1
  printf '\n  %s%s Selected:%s %s (%s)\n' "${CG}" "${G_OK}" "${C0}" "${MODEL_NAME}" "${MODEL_PATH}"
  ui_sleep 0.4
}

wizard_step_embedding_slot() {
  local ngpus choice slot default="1"
  ngpus="$(gpu_count)"
  (( ngpus < 1 )) && ngpus=1
  (( ngpus >= 2 )) && default="2"

  WIZ_HINT="Step 2 ${G_SEP} GPU slot (single card)"
  ui_transition 2 "Selecting GPU slot..."

  if [[ "${UI_ANIM}" == "1" ]]; then
    ui_gpu_cards || true
    echo
  else
    ui_gpu_cards || true
  fi

  ui_rule
  printf '  %sSelect GPU slot:%s\n\n' "${CB}" "${C0}"
  printf '  %sTip:%s GPU 2 is typical when LLM uses GPU 1 (cuda:0)\n\n' "${CD}" "${C0}"

  local opts=()
  local i=0
  while (( i < ngpus && i < 4 )); do
    local star=""
    [[ "${i}" == "1" ]] && star="${G_STAR} "
    opts+=("[$((i + 1))] ${star}GPU $((i + 1))  ${G_DASH}  cuda:${i}")
    i=$((i + 1))
  done
  opts+=("[C]   Custom slot")

  ui_menu_pick "Choice" "${default}" "${opts[@]}"
  choice="${UI_CHOICE}"

  case "${choice}" in
    1) slot="0" ;;
    2) slot="1" ;;
    3) slot="2" ;;
    4) slot="3" ;;
    [Cc]|[Cc][Uu][Ss][Tt])
      slot="$(ui_prompt "Enter slot id" "1")"
      ;;
    *)
      printf '  %s%s invalid choice%s\n' "${CR}" "${G_FAIL}" "${C0}" >&2
      return 1
      ;;
  esac

  [[ "${slot}" =~ ^[0-9]+$ ]] || {
    printf '  %s%s invalid slot: %s%s\n' "${CR}" "${G_FAIL}" "${slot}" "${C0}" >&2
    return 1
  }

  SLOT="${slot}"
  printf '\n  %s%s Selected slot:%s %s\n' "${CG}" "${G_OK}" "${C0}" "${SLOT}"
  ui_sleep 0.4
}

wizard_step_embedding_port() {
  local choice port=20001 default="1"

  WIZ_HINT="Step 3 ${G_SEP} HTTP port"
  ui_transition 3 "Choosing service port..."

  ui_rule
  printf '  %sSelect HTTP port:%s\n\n' "${CB}" "${C0}"

  port_status_label() {
    port_in_use "${1}" && printf '%sin use%s' "${CY}" "${C0}" || printf '%sfree%s' "${CG}" "${C0}"
  }

  ui_menu_pick "Choice" "${default}" \
    "[1] ${G_STAR} Port 20001  ${G_DASH}  $(port_status_label 20001)" \
    "[2]   Port 20002  ${G_DASH}  $(port_status_label 20002)" \
    "[3]   Port 20003  ${G_DASH}  $(port_status_label 20003)" \
    "[C]   Custom port"
  choice="${UI_CHOICE}"

  case "${choice}" in
    1|"") port=20001 ;;
    2) port=20002 ;;
    3) port=20003 ;;
    [Cc]|[Cc][Uu][Ss][Tt])
      port="$(ui_prompt "Enter port" "20001")"
      ;;
    *)
      printf '  %s%s invalid choice%s\n' "${CR}" "${G_FAIL}" "${C0}" >&2
      return 1
      ;;
  esac

  validate_port "${port}" || return 1
  PORT="${port}"

  if port_in_use "${PORT}"; then
    printf '\n  %s%s Port %s is in use %s Replace/Abort at confirm%s\n' \
      "${CY}" "${G_WARN}" "${PORT}" "${G_DASH}" "${C0}"
  else
    printf '\n  %s%s Port %s is available%s\n' "${CG}" "${G_OK}" "${PORT}" "${C0}"
  fi
  ui_sleep 0.4
}

embedding_wizard_confirm() {
  ui_clear
  echo
  printf '  %s%s' "${CHI}" "${G_TL}"
  ui_rule_char "${G_H}" $((ui_width - 4))
  printf '%s%s\n' "${G_TR}" "${C0}"
  printf '  %s%s%s  %sLaunch Summary%s %s%s%s\n' \
    "${CHI}" "${G_V}" "${C0}" "${CB}" "${CHI}" "${G_V}" "${C0}"
  printf '  %s%s' "${CHI}" "${G_V}"
  ui_rule_char "${G_H}" $((ui_width - 4))
  printf '%s\n' "${C0}"

  resolve_mem_fraction 2>/dev/null || true
  local mem_note=""
  if [[ "${EMBED_MODEL_SIZE}" == "4b" ]]; then
    mem_note=" (leaves room for reranker on same GPU)"
  fi

  local rows=(
    "Model|${MODEL_NAME}"
    "Model path|${MODEL_PATH}"
    "GPU slot|${SLOT}"
    "HTTP port|${PORT}"
    "VRAM cap|mem-fraction-static=${MEM_FRACTION_STATIC}${mem_note}"
    "Mode|embedding (--is-embedding)"
  )
  local row key val
  for row in "${rows[@]}"; do
    key="${row%%|*}"
    val="${row#*|}"
    printf '  %s%s%s  %-14s %s%s%s %s%s%s\n' \
      "${CHI}" "${G_V}" "${C0}" "${key}:" "${CW}" "${val}" "${CHI}" "${G_V}" "${C0}"
  done

  printf '  %s%s' "${CHI}" "${G_BL}"
  ui_rule_char "${G_H}" $((ui_width - 4))
  printf '%s%s\n\n' "${G_BR}" "${C0}"

  local existing_pids model_re
  model_re="$(wizard_escape_regex "${MODEL_PATH}")"
  existing_pids="$(wizard_find_existing_pids "${model_re}" "${PORT}")"
  if [[ -n "${existing_pids// /}" ]]; then
    wizard_prompt_replace_abort "${existing_pids}" || return 1
  fi

  if ! ui_prompt_yes "Launch embedding server now?" "y"; then
    printf '\n  %sAborted.%s\n' "${CY}" "${C0}"
    WIZ_LAUNCH_ABORT=1
    return 1
  fi

  printf '\n  %s%s Launching...%s\n\n' "${CG}" "${G_ROCKET}" "${C0}"
}

run_embedding_wizard() {
  ui_init_glyphs
  WIZ_REPLACE=0
  WIZ_LAUNCH_ABORT=0

  wizard_step_embedding_size || return 1
  wizard_step_embedding_slot || return 1
  wizard_step_embedding_port || return 1
  embedding_wizard_confirm || return 0
}
