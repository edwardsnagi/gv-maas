#!/usr/bin/env bash
# Fancy 3-step terminal wizard for gv-maas launch scripts.
# Source from model scripts; do not execute directly.

ui_width="${UI_WIDTH:-76}"
UI_ANIM="${UI_ANIM:-1}"

ui_init_glyphs() {
  local use_utf8=0

  # Default ASCII — avoids mojibake on HPC terminals. Set UI_UTF8=1 for unicode box art.
  if [[ "${UI_UTF8:-0}" == "1" ]]; then
    use_utf8=1
  fi

  if (( use_utf8 )); then
    G_TL='╔'; G_TR='╗'; G_BL='╚'; G_BR='╝'
    G_H='═'; G_V='║'; G_LT='╭'; G_LB='╰'
    G_BAR_F='█'; G_BAR_E='░'
    G_OK='✔'; G_FAIL='✖'; G_WARN='⚠'; G_ROCKET='🚀'
    G_DOT_ON='◉'; G_DOT_OFF='●'
    G_SPINNER='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    G_TRANS='◐◓◑◒'
    G_PULSE='▁▂▃▄▅▆▇█▇▆▅▄▃▂'
    G_SEP='·'; G_ARROW='→'; G_STAR='★'; G_DASH='—'
  else
    G_TL='+'; G_TR='+'; G_BL='+'; G_BR='+'
    G_H='-'; G_V='|'; G_LT='+'; G_LB='+'
    G_BAR_F='#'; G_BAR_E='.'
    G_OK='[OK]'; G_FAIL='[X]'; G_WARN='[!]'; G_ROCKET='>>'
    G_DOT_ON='*'; G_DOT_OFF='o'
    G_SPINNER='|/-\\'
    G_TRANS='|/-\\'
    G_PULSE='...'
    G_SEP='-'; G_ARROW='->'; G_STAR='*'; G_DASH='-'
  fi
}

# ── ANSI palette ─────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  C0=$'\033[0m'
  CB=$'\033[1m'
  CD=$'\033[2m'
  CC=$'\033[36m'
  CM=$'\033[35m'
  CG=$'\033[32m'
  CY=$'\033[33m'
  CR=$'\033[31m'
  CBU=$'\033[34m'
  CW=$'\033[97m'
  CBG=$'\033[48;5;236m'
  CACC=$'\033[38;5;45m'
  CHI=$'\033[38;5;213m'
else
  C0= CB= CD= CC= CM= CG= CY= CR= CBU= CW= CBG= CACC= CHI=
fi

ui_hide_cursor() { [[ -t 1 ]] && printf '\033[?25l' || true; }
ui_show_cursor() { [[ -t 1 ]] && printf '\033[?25h' || true; }

ui_clear() {
  [[ -t 1 ]] && printf '\033[2J\033[H' || printf '\n%.0s' {1..3}
}

ui_sleep() {
  [[ "${UI_ANIM}" == "1" ]] && sleep "${1:-0.15}" || true
}

ui_spinner() {
  local msg="${1}" frames i=0 n
  frames="${G_SPINNER:-|/-\\}"
  n=${#frames}
  ui_hide_cursor
  while [[ $# -gt 1 ]]; do
    shift
    if "$@"; then
      break
    fi
    printf '\r  %s %s%s%s' "${frames:i%n:1}" "${CD}" "${msg}" "${C0}"
    i=$((i + 1))
    sleep 0.08
  done
  printf '\r\033[K'
  ui_show_cursor
}

ui_spinner_run() {
  local msg="${1}" frames i=0 n rc=0
  shift
  frames="${G_SPINNER:-|/-\\}"
  n=${#frames}
  ui_hide_cursor
  ("$@") &
  local pid=$!
  while kill -0 "${pid}" 2>/dev/null; do
    printf '\r  %s %s%s%s' "${frames:i%n:1}" "${CC}" "${msg}" "${C0}"
    i=$((i + 1))
    sleep 0.08
  done
  wait "${pid}" || rc=$?
  printf '\r\033[K  %s %s%s%s\n' "${G_OK}" "${CG}" "${msg}" "${C0}"
  ui_show_cursor
  return "${rc}"
}

ui_typewriter() {
  local text="${1}" delay="${2:-0.012}" ch
  [[ "${UI_ANIM}" != "1" ]] && { printf '%s\n' "${text}"; return; }
  for ((i = 0; i < ${#text}; i++)); do
    ch="${text:i:1}"
    printf '%s' "${ch}"
    sleep "${delay}"
  done
  printf '\n'
}

ui_progress_bar() {
  local step="${1}" total="${2}" bar_w=24 filled empty bar="" i
  filled=$((step * bar_w / total))
  empty=$((bar_w - filled))
  for ((i = 0; i < filled; i++)); do bar+="${G_BAR_F}"; done
  for ((i = 0; i < empty; i++)); do bar+="${G_BAR_E}"; done
  printf '  %s[%s%s%s]%s  Step %s/%s\n' "${CD}" "${CACC}" "${bar}" "${C0}" "${CD}" "${step}" "${total}"
}

ui_banner() {
  local title="${1}" subtitle="${2}"
  ui_clear
  echo
  printf '  %s%s' "${CC}" "${G_TL}"
  ui_rule_char "${G_H}" $((ui_width - 4))
  printf '%s%s\n' "${G_TR}" "${C0}"
  printf '  %s%s%s  %s%-*s%s %s%s%s\n' \
    "${CC}" "${G_V}" "${C0}" "${CB}" $((ui_width - 8)) "${title}" "${CC}" "${G_V}" "${C0}"
  if [[ -n "${subtitle}" ]]; then
    printf '  %s%s%s  %s%-*s%s %s%s%s\n' \
      "${CC}" "${G_V}" "${C0}" "${CD}" $((ui_width - 8)) "${subtitle}" "${CC}" "${G_V}" "${C0}"
  fi
  printf '  %s%s' "${CC}" "${G_BL}"
  ui_rule_char "${G_H}" $((ui_width - 4))
  printf '%s%s\n' "${G_BR}" "${C0}"
  echo
}

ui_rule_char() {
  local char="${1}" count="${2}"
  printf '%*s' "${count}" '' | tr ' ' "${char}"
}

ui_rule() {
  printf '  %s%s%s\n' "${CD}" "$(ui_rule_char "${1:-${G_H}}" $((ui_width - 4)))" "${C0}"
}

ui_step_intro() {
  local step="${1}" total="${2}" title="${3}" hint="${4}"
  ui_banner "${title}" "${hint}"
  ui_progress_bar "${step}" "${total}"
  echo
}

ui_transition() {
  local next="${1}" msg="${2:-Loading next step...}"
  if [[ "${UI_ANIM}" == "1" ]]; then
    local frames="${G_TRANS}" i=0
    for _ in $(seq 1 8); do
      printf '\r  %s %s%s%s' "${frames:i%4:1}" "${CHI}" "${msg}" "${C0}"
      i=$((i + 1))
      sleep 0.06
    done
    printf '\r\033[K'
  fi
  ui_step_intro "${next}" 3 "${WIZ_MODEL}" "${WIZ_HINT}"
}

ui_mem_bar() {
  local used="${1}" total="${2}" bar_w=18 pct=0 filled=0 empty=0 bar="" i
  (( total > 0 )) && pct=$((used * 100 / total))
  filled=$((pct * bar_w / 100))
  empty=$((bar_w - filled))
  for ((i = 0; i < filled; i++)); do bar+="${G_BAR_F}"; done
  for ((i = 0; i < empty; i++)); do bar+="${G_BAR_E}"; done
  local color="${CG}"
  (( pct > 70 )) && color="${CY}"
  (( pct > 90 )) && color="${CR}"
  printf '%s%s%s' "${color}" "${bar}" "${C0}"
}

# nvidia-smi nounits fields are MiB; format as one-decimal GB for display.
ui_mib_gb() {
  local mib="${1}" gb_x10=0
  [[ "${mib}" =~ ^[0-9]+$ ]] || mib=0
  gb_x10=$((mib * 10 / 1024))
  printf '%d.%d' $((gb_x10 / 10)) $((gb_x10 % 10))
}

ui_gpu_cards() {
  if ! command -v nvidia-smi >/dev/null 2>&1; then
    printf '  %s(no GPU data — nvidia-smi missing)%s\n' "${CY}" "${C0}"
    return 1
  fi

  while IFS=, read -r idx name total free used util; do
    name="${name# }"
    total="${total// /}"
    free="${free// /}"
    used="${used// /}"
    util="${util// /}"
    [[ "${used}" =~ ^[0-9]+$ ]] || used=$((total - free))
    local gpu_num=$((idx + 1)) status="idle" sc="${CG}" dot="${G_DOT_OFF}"
    if [[ "${util}" =~ ^[0-9]+$ && "${util}" -gt 5 ]]; then
      status="busy"; sc="${CY}"; dot="${G_DOT_ON}"
    elif [[ "${used}" =~ ^[0-9]+$ && "${total}" =~ ^[0-9]+$ && "${total}" -gt 0 && $((used * 100 / total)) -gt 5 ]]; then
      status="in use"; sc="${CY}"; dot="${G_DOT_ON}"
    fi
    printf '  %s%s- GPU %-2s %s%s%s  %s(cuda:%s)%s\n' \
      "${CC}" "${G_LT}" "${gpu_num}" "${CB}" "${name:0:28}" "${C0}" "${CD}" "${idx}" "${C0}"
    printf '  %s%s%s  VRAM  ' "${CC}" "${G_V}" "${C0}"
    ui_mem_bar "${used}" "${total}"
    printf '  %s%s%s / %s GB used  %s(%s GB free)%s   %s%s %s%s\n' \
      "${CW}" "$(ui_mib_gb "${used}")" "${C0}" "$(ui_mib_gb "${total}")" \
      "${CD}" "$(ui_mib_gb "${free}")" "${C0}" "${sc}" "${dot}" "${status}" "${C0}"
    printf '  %s%s%s  Util  %s%3s%%%s\n' "${CC}" "${G_V}" "${C0}" "${CW}" "${util}" "${C0}"
    printf '  %s%s%s\n' "${CC}" "${G_LB}" "$(ui_rule_char "${G_H}" $((ui_width - 8)))"
    echo
  done < <(
    nvidia-smi --query-gpu=index,name,memory.total,memory.free,memory.used,utilization.gpu \
      --format=csv,noheader,nounits 2>/dev/null
  )
}

gpu_count() {
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi -L 2>/dev/null | wc -l
  else
    echo 0
  fi
}

port_in_use() {
  local port="${1}"
  ss -ltn 2>/dev/null | grep -q ":${port} "
}

validate_port() {
  local port="${1}"
  [[ "${port}" =~ ^[0-9]+$ ]] && (( port >= 1024 && port <= 65535 )) || {
    printf '  %s%s invalid port: %s (use 1024-65535)%s\n' "${CR}" "${G_FAIL}" "${port}" "${C0}" >&2
    return 1
  }
}

validate_positive_int() {
  local name="${1}" value="${2}"
  [[ "${value}" =~ ^[0-9]+$ ]] && (( value >= 1 )) || {
    printf '  %s%s %s must be a positive integer, got: %s%s\n' "${CR}" "${G_FAIL}" "${name}" "${value}" "${C0}" >&2
    return 1
  }
}

count_slots() {
  local slots="${1}" n=1
  [[ "${slots}" == *","* ]] || { echo 1; return; }
  n="${slots//[^,]/}"
  echo $(( ${#n} + 1 ))
}

trim_slots() {
  local slots="${1}" keep="${2}" out="" part n=0
  IFS=',' read -ra parts <<< "${slots}"
  for part in "${parts[@]}"; do
    (( n >= keep )) && break
    [[ -z "${out}" ]] && out="${part}" || out="${out},${part}"
    n=$((n + 1))
  done
  printf '%s' "${out}"
}

slots_for_range() {
  local start="${1}" count="${2}" i slots=""
  for ((i = 0; i < count; i++)); do
    [[ -z "${slots}" ]] && slots="$((start + i))" || slots="${slots},$((start + i))"
  done
  printf '%s' "${slots}"
}

validate_parallel_plan() {
  local slots="${1}" tp="${2}" dp="${3}"
  local slot_count required
  slot_count="$(count_slots "${slots}")"
  required=$((tp * dp))

  if (( slot_count < required )); then
    printf '  %s%s need >= %s slot(s) for tp=%s x dp=%s, got %s (%s)%s\n' \
      "${CR}" "${G_FAIL}" "${required}" "${tp}" "${dp}" "${slot_count}" "${slots}" "${C0}" >&2
    return 1
  fi

  if (( slot_count > required )); then
    slots="$(trim_slots "${slots}" "${required}")"
  fi
  printf '%s' "${slots}"
}

ui_normalize_choice() {
  local v="${1}" line
  v="${v//$'\r'/}"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  line="${v%%$'\n'*}"
  if [[ "${line}" =~ ^\[([0-9]+)\] ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  elif [[ "${line}" =~ ^([0-9]+) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  elif [[ "${line}" =~ ^[Cc]$ ]]; then
    printf 'C'
  elif [[ "${line}" =~ ^[Rr](eplace)?$ ]]; then
    printf 'replace'
  elif [[ "${line}" =~ ^[Aa](bort)?$ ]]; then
    printf 'abort'
  else
    printf '%s' "${line}"
  fi
}

UI_CHOICE=""

ui_menu_pick() {
  local prompt="${1}" default="${2}"
  shift 2
  local options=("$@") value="" opt
  for opt in "${options[@]}"; do
    printf '    %s%s%s\n' "${CW}" "${opt}" "${C0}"
  done
  echo
  read -rp "$(printf '  %s%s%s %s [%s]: ' "${CACC}" "${G_ARROW}" "${C0}" "${prompt}" "${default}")" value
  value="${value:-${default}}"
  UI_CHOICE="$(ui_normalize_choice "${value}")"
}

ui_prompt() {
  local label="${1}" default="${2}" value=""
  read -rp "$(printf '  %s%s%s %s [%s]: ' "${CACC}" "${G_ARROW}" "${C0}" "${label}" "${default}")" value
  [[ -z "${value}" ]] && value="${default}"
  printf '%s' "${value}"
}

ui_prompt_yes() {
  local label="${1}" default="${2}" value="" hint="y/n"
  [[ "${default}" == "y" ]] && hint="Y/n"
  [[ "${default}" == "n" ]] && hint="y/N"
  read -rp "$(printf '  %s%s%s %s [%s]: ' "${CACC}" "${G_ARROW}" "${C0}" "${label}" "${hint}")" value
  value="${value:-${default}}"
  [[ "${value}" =~ ^[Yy] ]]
}

wizard_escape_regex() {
  printf '%s' "$1" | sed 's/[][\\.*^$()+?{|]/\\&/g'
}

wizard_find_existing_pids() {
  local model_re="${1}" port="${2}" pids=""
  pids="$(pgrep -f "sglang\\.launch_server.*${model_re}" 2>/dev/null | tr '\n' ' ' || true)"
  if [[ -z "${pids// /}" ]]; then
    pids="$(pgrep -f "sglang\\.launch_server.*--port ${port}" 2>/dev/null | tr '\n' ' ' || true)"
  fi
  printf '%s' "${pids}" | xargs -r echo
}

wizard_prompt_replace_abort() {
  local pids="${1}" choice
  echo >&2
  ui_rule >&2
  printf '  %s%s Existing instance detected%s\n' "${CY}" "${G_WARN}" "${C0}" >&2
  printf '    PIDs: %s\n' "${pids}" >&2
  printf '    Port: %s\n\n' "${PORT}" >&2

  ui_menu_pick "Action" "1" \
    "[1] Replace ${G_DASH} stop existing and launch new instance" \
    "[2] Abort ${G_DASH} exit without changes"
  choice="${UI_CHOICE}"

  case "${choice}" in
    1|replace)
      WIZ_REPLACE=1
      return 0
      ;;
    2|abort)
      WIZ_LAUNCH_ABORT=1
      printf '\n  %sAborted.%s\n' "${CY}" "${C0}" >&2
      return 1
      ;;
    *)
      printf '  %s%s Please choose 1 (Replace) or 2 (Abort)%s\n' "${CR}" "${G_FAIL}" "${C0}" >&2
      wizard_prompt_replace_abort "${pids}"
      ;;
  esac
}

# ── Step 1: GPU slots ────────────────────────────────────────────────────────
wizard_step_slots() {
  local ngpus="${1}" choice slots="" default="1"

  WIZ_HINT="Step 1 ${G_SEP} Pick GPU slot(s) for this model"
  ui_step_intro 1 3 "${WIZ_MODEL}" "${WIZ_HINT}"

  if [[ "${UI_ANIM}" == "1" ]]; then
    ui_typewriter "  Scanning GPU topology..." 0.008
    ui_spinner_run "Reading nvidia-smi" sleep 0.5
    echo
  fi

  ui_gpu_cards || true

  ui_rule
  printf '  %sSelect slot configuration:%s\n\n' "${CB}" "${C0}"

  local opts=()
  opts+=("[1] ${G_STAR} Slot 0 only              ${G_ARROW}  0          (recommended)")
  if (( ngpus >= 2 )); then
    opts+=("[2]   Slots 0,1                ${G_ARROW}  0,1")
    opts+=("[3]   Slots 0,1,2,3            ${G_ARROW}  0,1,2,3    (all ${ngpus} GPUs)")
  fi
  opts+=("[C]   Custom slots             ${G_ARROW}  e.g. 1,3")

  ui_menu_pick "Choice" "${default}" "${opts[@]}"
  choice="${UI_CHOICE}"

  case "${choice}" in
    1|"") slots="0" ;;
    2) slots="0,1" ;;
    3) slots="$(slots_for_range 0 "${ngpus}")" ;;
    [Cc]|[Cc][Uu][Ss][Tt])
      slots="$(ui_prompt "Enter slots (comma-separated)" "0")"
      ;;
    *)
      printf '  %s%s invalid choice%s\n' "${CR}" "${G_FAIL}" "${C0}" >&2
      return 1
      ;;
  esac

  [[ "${slots}" =~ ^[0-9]+(,[0-9]+)*$ ]] || {
    printf '  %s%s invalid slots: %s%s\n' "${CR}" "${G_FAIL}" "${slots}" "${C0}" >&2
    return 1
  }

  SLOT="${slots}"
  printf '\n  %s%s Selected slots:%s %s%s%s\n' "${CG}" "${G_OK}" "${C0}" "${CB}" "${SLOT}" "${C0}"
  ui_sleep 0.4
}

# ── Step 2: TP / DP ──────────────────────────────────────────────────────────
wizard_step_parallel() {
  local n choice tp=1 dp=1
  n="$(count_slots "${SLOT}")"

  WIZ_HINT="Step 2 ${G_SEP} Tensor / Data parallel"
  ui_transition 2 "Configuring parallelism..."

  printf '  %sSelected slots:%s %s%s%s   (%s GPU(s) available)\n\n' \
    "${CD}" "${C0}" "${CB}" "${SLOT}" "${C0}" "${n}"
  printf '  %sConstraint:%s tp x dp <= %s\n\n' "${CD}" "${C0}" "${n}"

  ui_rule
  printf '  %sSelect parallel strategy:%s\n\n' "${CB}" "${C0}"

  local opts=() default="1"
  opts+=("[1] ${G_STAR} tp=1  dp=1   Single replica, no split       (recommended)")
  if (( n >= 2 )); then
    opts+=("[2]   tp=2  dp=1   Tensor Parallel ${G_DASH} split model across 2 GPUs")
    opts+=("[3]   tp=1  dp=2   Data Parallel ${G_DASH} 2 model replicas")
  fi
  if (( n >= 4 )); then
    opts+=("[4]   tp=4  dp=1   Tensor Parallel ${G_DASH} 4-way split")
    opts+=("[5]   tp=2  dp=2   Hybrid TP+DP (4 GPUs)")
  fi
  opts+=("[C]   Custom tp / dp")

  ui_menu_pick "Choice" "${default}" "${opts[@]}"
  choice="${UI_CHOICE}"

  case "${choice}" in
    1|"") tp=1; dp=1 ;;
    2) tp=2; dp=1 ;;
    3) tp=1; dp=2 ;;
    4) tp=4; dp=1 ;;
    5) tp=2; dp=2 ;;
    [Cc]|[Cc][Uu][Ss][Tt])
      tp="$(ui_prompt "Tensor parallel (tp-size)" "1")"
      dp="$(ui_prompt "Data parallel (dp-size)" "1")"
      validate_positive_int "tp-size" "${tp}" || return 1
      validate_positive_int "dp-size" "${dp}" || return 1
      ;;
    *)
      printf '  %s%s invalid choice%s\n' "${CR}" "${G_FAIL}" "${C0}" >&2
      return 1
      ;;
  esac

  if (( tp * dp > n )); then
    printf '  %s%s tp x dp=%s exceeds %s selected slot(s)%s\n' \
      "${CR}" "${G_FAIL}" "$((tp * dp))" "${n}" "${C0}" >&2
    return 1
  fi

  TP_SIZE="${tp}"
  DP_SIZE="${dp}"
  SLOT="$(validate_parallel_plan "${SLOT}" "${TP_SIZE}" "${DP_SIZE}")" || return 1

  printf '\n  %s%s Parallel plan:%s tp=%s  dp=%s  %s  %s GPU(s)\n' \
    "${CG}" "${G_OK}" "${C0}" "${TP_SIZE}" "${DP_SIZE}" "${G_ARROW}" "$((TP_SIZE * DP_SIZE))"
  ui_sleep 0.4
}

# ── Step 3: Port ─────────────────────────────────────────────────────────────
wizard_step_port() {
  local choice port=10000

  WIZ_HINT="Step 3 ${G_SEP} HTTP port"
  ui_transition 3 "Choosing service port..."

  ui_rule
  printf '  %sSelect HTTP port:%s\n\n' "${CB}" "${C0}"

  local opts=() default="1"
  port_status_label() {
    port_in_use "${1}" && printf '%sin use%s' "${CY}" "${C0}" || printf '%sfree%s' "${CG}" "${C0}"
  }
  opts+=("[1] ${G_STAR} Port 10000  ${G_DASH}  $(port_status_label 10000)")
  opts+=("[2]   Port 10001  ${G_DASH}  $(port_status_label 10001)")
  opts+=("[3]   Port 10002  ${G_DASH}  $(port_status_label 10002)")
  opts+=("[4]   Port 8080  ${G_DASH}  $(port_status_label 8080)")
  opts+=("[C]   Custom port")

  ui_menu_pick "Choice" "${default}" "${opts[@]}"
  choice="${UI_CHOICE}"

  case "${choice}" in
    1|"") port=10000 ;;
    2) port=10001 ;;
    3) port=10002 ;;
    4) port=8080 ;;
    [Cc]|[Cc][Uu][Ss][Tt])
      port="$(ui_prompt "Enter port" "10000")"
      ;;
    *)
      printf '  %s%s invalid choice%s\n' "${CR}" "${G_FAIL}" "${C0}" >&2
      return 1
      ;;
  esac

  validate_port "${port}" || return 1
  PORT="${port}"

  if port_in_use "${PORT}"; then
    printf '\n  %s%s Port %s is in use %s you will be asked Replace/Abort before launch%s\n' \
      "${CY}" "${G_WARN}" "${PORT}" "${G_DASH}" "${C0}"
  else
    printf '\n  %s%s Port %s is available%s\n' "${CG}" "${G_OK}" "${PORT}" "${C0}"
  fi
  ui_sleep 0.4
}

# ── Final confirm ────────────────────────────────────────────────────────────
wizard_confirm() {
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

  local rows=(
    "Model|${WIZ_MODEL}"
    "GPU slot(s)|${SLOT}"
    "Tensor parallel|tp = ${TP_SIZE}"
    "Data parallel|dp = ${DP_SIZE}"
    "GPUs used|${TP_SIZE} x ${DP_SIZE} = $((TP_SIZE * DP_SIZE))"
    "HTTP port|${PORT}"
  )
  local row key val
  for row in "${rows[@]}"; do
    key="${row%%|*}"
    val="${row#*|}"
    printf '  %s%s%s  %-18s %s%s%s %s%s%s\n' \
      "${CHI}" "${G_V}" "${C0}" "${key}:" "${CW}" "${val}" "${CHI}" "${G_V}" "${C0}"
  done

  printf '  %s%s' "${CHI}" "${G_BL}"
  ui_rule_char "${G_H}" $((ui_width - 4))
  printf '%s%s\n\n' "${G_BR}" "${C0}"

  if [[ "${UI_ANIM}" == "1" ]]; then
    local frames="${G_PULSE}" i=0 flen=${#G_PULSE}
    (( flen < 1 )) && flen=3
    for _ in $(seq 1 16); do
      printf '\r  %s%s%s Confirm to launch %s' "${CACC}" "${frames:i%flen:1}" "${C0}" "${frames:i%flen:1}"
      i=$((i + 1))
      sleep 0.05
    done
    printf '\r\033[K'
  fi

  local existing_pids model_re
  model_re="$(wizard_escape_regex "${WIZ_MODEL_PATH:-}")"
  existing_pids="$(wizard_find_existing_pids "${model_re}" "${PORT}")"
  if [[ -n "${existing_pids// /}" ]]; then
    wizard_prompt_replace_abort "${existing_pids}" || return 1
  fi

  if ! ui_prompt_yes "Launch server now?" "y"; then
    printf '\n  %sAborted.%s\n' "${CY}" "${C0}"
    exit 0
  fi

  printf '\n  %s%s Launching...%s\n\n' "${CG}" "${G_ROCKET}" "${C0}"
}

run_launch_wizard() {
  local model_name="${1:-Model}" model_path="${2:-}" ngpus
  ui_init_glyphs
  WIZ_MODEL="${model_name}"
  WIZ_MODEL_PATH="${model_path}"
  WIZ_REPLACE=0
  WIZ_LAUNCH_ABORT=0
  ngpus="$(gpu_count)"
  (( ngpus < 1 )) && ngpus=1

  ui_hide_cursor
  trap 'ui_show_cursor' EXIT

  wizard_step_slots "${ngpus}" || { ui_show_cursor; return 1; }
  wizard_step_parallel || { ui_show_cursor; return 1; }
  wizard_step_port || { ui_show_cursor; return 1; }
  wizard_confirm || { ui_show_cursor; trap - EXIT; return 0; }

  ui_show_cursor
  trap - EXIT
}

ui_init_glyphs
