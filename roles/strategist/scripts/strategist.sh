#!/usr/bin/env bash
# Strategist (Стратег) Agent Runner
# Запускает Claude Code с заданным сценарием
# Targets: Linux, macOS
#
# Exit codes:
#   0 — успех
#   1 — ошибка (файл не найден, неверный аргумент)
#   2 — уже запущен (lock exists — для планировщика)
#   3 — не удалось создать temp dir для lock

set -euo pipefail

# Конфигурация
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_DIR="$(dirname "${SCRIPT_DIR}")"
readonly REPO_DIR
# IWE env (scripts/ → role/ → roles/ → repo/ → workspace)
_iwe_ws="$(cd "${SCRIPT_DIR}/../../../.." && pwd)" \
  || { echo "ERROR: Cannot resolve workspace dir from ${SCRIPT_DIR}" >&2; exit 1; }
ENV_FILE="${HOME}/.$(basename "${_iwe_ws}")/env"
readonly ENV_FILE
_ws_slug="${_iwe_ws//\//-}"
RHYTHM_CONFIG="${HOME}/.claude/projects/${_ws_slug}/memory/day-rhythm-config.yaml"
readonly RHYTHM_CONFIG
unset _iwe_ws _ws_slug

# Content-validate env file before sourcing (guard against shell injection)
function _validate_env_file() {
  local filepath="${1}"
  if grep -qE '^[[:blank:]]*(eval|source|\.)[[:blank:]]' "${filepath}" 2>/dev/null; then
    echo "ERROR: env file contains dangerous patterns: ${filepath}" >&2
    exit 1
  fi
}

if [[ -f "${ENV_FILE}" ]]; then
  _validate_env_file "${ENV_FILE}"
  set -a
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
  set +a
else
  echo "IWE env not found: ${ENV_FILE}" >&2
  exit 1
fi

# Guard: required env vars must be set (fail-fast after sourcing)
: "${WORKSPACE_DIR:?WORKSPACE_DIR is not set — check ENV_FILE}"
: "${CLAUDE_PATH:?CLAUDE_PATH is not set — check ENV_FILE}"

# Guard: python3 required for date localisation and JSON encoding
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required but not found" >&2; exit 1; }

readonly WORKSPACE="${WORKSPACE_DIR}/DS-strategy"
readonly PROMPTS_DIR="${REPO_DIR}/prompts"
readonly LOG_DIR="${HOME}/.local/state/logs/strategist"

# Создаём папку для логов
mkdir -p "${LOG_DIR}"

# Определяем день недели и тип сценария
DAY_OF_WEEK=$(date +%u) # 1=Mon, 7=Sun
readonly DAY_OF_WEEK
DATE=$(date +%Y-%m-%d)
readonly DATE

# Лог файл
LOG_FILE="${LOG_DIR}/${DATE}.log"
readonly LOG_FILE

function log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ${1}"
  echo "${msg}" >> "${LOG_FILE}"
  case "${1}" in
    ERROR:* | WARN:*) echo "${msg}" >&2 ;;
    *) echo "${msg}" ;;
  esac
}

function notify() {
  local title="${1}"
  local message="${2}"
  if [[ "${OSTYPE}" == "darwin"* ]]; then
    printf 'display notification "%s" with title "%s"' "${message}" "${title}" | osascript 2>/dev/null || true
  elif command -v notify-send &>/dev/null; then
    notify-send "${title}" "${message}" 2>/dev/null || true
  fi
}

function notify_telegram() {
  local scenario="${1}"
  "$(dirname "$(dirname "${SCRIPT_DIR}")")/synchronizer/scripts/notify.sh" strategist "${scenario}" >> "${LOG_FILE}" 2>&1 || true
}

function run_claude() {
  local command_file="${1}"
  local command_path="${PROMPTS_DIR}/${command_file}.md"

  # Traversal validation: command_file must not contain path separators or ..
  case "${command_file}" in
    */* | *..*  )
      log "ERROR: Invalid command_file (traversal): ${command_file}"
      exit 1
      ;;
  esac

  if [[ ! -f "${command_path}" ]]; then
    log "ERROR: Command file not found: ${command_path}"
    exit 1
  fi

  # Читаем содержимое команды
  local prompt
  prompt=$(cat "${command_path}")

  # Inject current date + day of week (prevents LLM calendar arithmetic errors)
  local ru_date_context
  ru_date_context=$(python3 -c "
import datetime
days = ['Понедельник','Вторник','Среда','Четверг','Пятница','Суббота','Воскресенье']
months = ['января','февраля','марта','апреля','мая','июня','июля','августа','сентября','октября','ноября','декабря']
d = datetime.date.today()
print(f'{d.day} {months[d.month-1]} {d.year}, {days[d.weekday()]}')
")
  prompt="[Системный контекст] Сегодня: ${ru_date_context}. ISO: ${DATE}. День недели №${DAY_OF_WEEK} (1=Пн..7=Вс).

${prompt}"

  log "Starting scenario: ${command_file}"
  log "Command file: ${command_path}"
  log "Date context: ${ru_date_context}"

  # Wrap cd + Claude in subshell to avoid mutating parent's working directory (AP-AR2)
  (
    cd "${WORKSPACE}" || { log "ERROR: Cannot cd to WORKSPACE: ${WORKSPACE}"; exit 1; }
    "${CLAUDE_PATH}" --dangerously-skip-permissions \
      --allowedTools "Read,Write,Edit,Glob,Grep,Bash" \
      -p "${prompt}" \
      >> "${LOG_FILE}" 2>&1
  )

  log "Completed scenario: ${command_file}"

  # Push changes to GitHub (чтобы бот мог читать через API)
  if git -C "${WORKSPACE}" diff --quiet origin/main..HEAD 2>/dev/null; then
    log "No unpushed commits"
  else
    git -C "${WORKSPACE}" pull --rebase >> "${LOG_FILE}" 2>&1 && log "Pulled (rebase)" || log "WARN: pull --rebase failed"
    git -C "${WORKSPACE}" push >> "${LOG_FILE}" 2>&1 && log "Pushed to GitHub" || log "WARN: git push failed"
  fi

  # Очистить staging area после Claude сессии (предотвращает staging leak в следующие скрипты)
  # НЕ трогаем working tree — только unstage orphaned changes
  git -C "${WORKSPACE}" reset --quiet 2>/dev/null || true
  log "Cleared staging area after Claude session"

  # macOS notification
  local summary
  # [BASH-SAFE-009, BASH-SAFE-016] grep no-match + SIGPIPE from head
  summary=$(tail -5 "${LOG_FILE}" | grep -v '^\[' | head -3) || true
  notify "Стратег: ${command_file}" "${summary}"
}

# Проверка: уже запускался ли сценарий сегодня
function already_ran_today() {
  local scenario="${1}"
  [[ -f "${LOG_FILE}" ]] && grep -q "Completed scenario: ${scenario}" "${LOG_FILE}"
}

# Global lock registry — populated by acquire_lock(), cleaned by _cleanup_locks()
_LOCK_FILES=()
_LOCK_DIRS=()

function _cleanup_locks() {
  local _exit_code
  _exit_code=$?
  local f d
  if [[ ${#_LOCK_FILES[@]} -gt 0 ]]; then
    for f in "${_LOCK_FILES[@]}"; do rm -f "${f}"; done
  fi
  if [[ ${#_LOCK_DIRS[@]} -gt 0 ]]; then
    for d in "${_LOCK_DIRS[@]}"; do rm -rf "${d}"; done
  fi
  exit "${_exit_code}"
}

trap _cleanup_locks EXIT INT TERM

# File-based lock to prevent concurrent execution (RunAtLoad + CalendarInterval race)
readonly LOCK_DIR="${LOG_DIR}/locks"
mkdir -p "${LOCK_DIR}"

function acquire_lock() {
  local scenario="${1}"
  local lockfile="${LOCK_DIR}/${scenario}.${DATE}.lock"
  local tempdir

  if ! tempdir=$(mktemp -d "${LOCK_DIR}/.lock.XXXXXX"); then
    log "ERROR: Cannot create temp dir for lock (scenario: ${scenario})"
    exit 3
  fi

  if ! ln -s "${tempdir}" "${lockfile}" 2>/dev/null; then
    rm -rf "${tempdir}"
    log "SKIP: ${scenario} already running (lock exists: ${lockfile})"
    exit 2  # non-zero → scheduler won't mark_done
  fi

  # Register lock artifacts for cleanup by _cleanup_locks()
  _LOCK_FILES+=("${lockfile}")
  _LOCK_DIRS+=("${tempdir}")
}

# Читаем strategy_day из конфига (L4 Personal)
STRATEGY_DAY_NAME=$(grep 'strategy_day:' "${RHYTHM_CONFIG}" 2>/dev/null | awk '{print $2}' || echo "monday")
readonly STRATEGY_DAY_NAME
# Конвертируем имя дня в номер (1=Mon..7=Sun)
case "${STRATEGY_DAY_NAME}" in
  monday)    STRATEGY_DAY_NUM=1 ;;
  tuesday)   STRATEGY_DAY_NUM=2 ;;
  wednesday) STRATEGY_DAY_NUM=3 ;;
  thursday)  STRATEGY_DAY_NUM=4 ;;
  friday)    STRATEGY_DAY_NUM=5 ;;
  saturday)  STRATEGY_DAY_NUM=6 ;;
  sunday)    STRATEGY_DAY_NUM=7 ;;
  *)         STRATEGY_DAY_NUM=1 ;; # fallback: monday
esac
readonly STRATEGY_DAY_NUM

function run_week_review() {
  acquire_lock "week-review"
  if already_ran_today "week-review"; then
    log "SKIP: week-review already completed today"
    exit 0
  fi
  log "Sunday: running week review"
  run_claude "week-review"
  # Fallback push for Knowledge Index (week-review creates a post there)
  local ki_repo="${WORKSPACE_DIR}/DS-Knowledge-Index"
  if git -C "${ki_repo}" log --oneline -1 --since="1 hour ago" --grep="week-review" 2>/dev/null | grep -q .; then
    git -C "${ki_repo}" push >> "${LOG_FILE}" 2>&1 && log "Pushed Knowledge Index (fallback)" || log "WARN: KI push failed"
  fi
  notify_telegram "week-review"
}

function run_note_review() {
  acquire_lock "note-review"
  log "Evening: running note review"
  # Canary: count bold notes before (exclude 🔄 — deferred ideas stay bold by design)
  local fleeting="${WORKSPACE}/inbox/fleeting-notes.md"
  local bold_before bold_new_before bold_after bold_new_after non_bold cleanup_output
  bold_before=$(grep -c '^\*\*' "${fleeting}" 2>/dev/null || echo 0)
  bold_new_before=$(grep '^\*\*' "${fleeting}" 2>/dev/null | grep -v '🔄' | grep -c '.' || echo 0)
  log "Canary: ${bold_before} bold total (${bold_new_before} new, $(( bold_before - bold_new_before )) deferred 🔄)"

  run_claude "note-review"

  # Canary: count bold notes after — only NEW bold (without 🔄) should decrease
  bold_after=$(grep -c '^\*\*' "${fleeting}" 2>/dev/null || echo 0)
  bold_new_after=$(grep '^\*\*' "${fleeting}" 2>/dev/null | grep -v '🔄' | grep -c '.' || echo 0)
  log "Canary: ${bold_after} bold total (${bold_new_after} new)"
  non_bold=$(grep -c '^[^*#>-]' "${fleeting}" 2>/dev/null || echo 0)
  log "Non-bold content lines: ${non_bold}"
  if [[ "${bold_new_after}" -ge "${bold_new_before}" ]] && [[ "${bold_new_before}" -gt 0 ]]; then
    log "WARN: Note-Review Step 10 may have failed — new bold notes did not decrease (${bold_new_before} → ${bold_new_after})"
  fi

  # Deterministic cleanup: archive non-bold, non-🔄 notes (safety net for LLM Step 10)
  log "Running deterministic cleanup..."
  cleanup_output=$(bash "${SCRIPT_DIR}/cleanup-processed-notes.sh" 2>&1) || true
  log "Cleanup: ${cleanup_output}"

  # If cleanup made changes, commit and push
  if ! git -C "${WORKSPACE}" diff --quiet -- inbox/fleeting-notes.md archive/notes/Notes-Archive.md 2>/dev/null; then
    git -C "${WORKSPACE}" add inbox/fleeting-notes.md archive/notes/Notes-Archive.md
    git -C "${WORKSPACE}" commit -m "chore: auto-cleanup processed notes from fleeting-notes.md" >> "${LOG_FILE}" 2>&1 || true
    git -C "${WORKSPACE}" pull --rebase >> "${LOG_FILE}" 2>&1 && log "Cleanup: pulled (rebase)" || log "WARN: cleanup pull --rebase failed"
    git -C "${WORKSPACE}" push >> "${LOG_FILE}" 2>&1 && log "Cleanup: pushed" || log "WARN: cleanup push failed"
  else
    log "Cleanup: no changes to commit"
  fi

  # Alert if LLM failed AND cleanup was needed (only for NEW bold, not deferred 🔄)
  if [[ "${bold_new_after}" -ge "${bold_new_before}" ]] && [[ "${bold_new_before}" -gt 0 ]]; then
    local alert_env="${HOME}/.config/aist/env"
    if [[ -f "${alert_env}" ]]; then
      _validate_env_file "${alert_env}"
      set -a
      # shellcheck source=/dev/null
      source "${alert_env}"
      set +a
      local alert_text alert_json
      alert_text="⚠️ <b>Note-Review canary</b>: Step 10 не сработал (${bold_new_before} → ${bold_new_after} new bold). Deterministic cleanup applied."
      alert_json=$(printf '%s' "${alert_text}" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')
      curl --fail --max-time 10 --connect-timeout 5 \
        -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "{\"chat_id\":\"${TELEGRAM_CHAT_ID}\",\"text\":${alert_json},\"parse_mode\":\"HTML\"}" \
        > /dev/null 2>&1 || true
    fi
  fi

  notify_telegram "note-review"
}

function main() {
  local scenario
  case "${1:-}" in
    "morning")
      # Определяем нужный сценарий: strategy_day → session-prep, иначе → day-plan
      if [[ "${DAY_OF_WEEK}" -eq "${STRATEGY_DAY_NUM}" ]]; then
        scenario="session-prep"
      else
        scenario="day-plan"
      fi

      # Защита от повторного запуска (RunAtLoad + CalendarInterval race condition)
      acquire_lock "${scenario}"
      if already_ran_today "${scenario}"; then
        log "SKIP: ${scenario} already completed today"
        exit 0
      fi

      if [[ "${DAY_OF_WEEK}" -eq "${STRATEGY_DAY_NUM}" ]]; then
        log "Strategy day (${STRATEGY_DAY_NAME}): running session prep"
        run_claude "session-prep"
        notify_telegram "session-prep"
      else
        log "Morning: running day plan"
        run_claude "day-plan"
        notify_telegram "day-plan"
      fi
      ;;
    "evening")
      log "Evening: running evening review"
      run_claude "evening"
      notify_telegram "evening"
      ;;
    "week-review")
      run_week_review
      ;;
    "session-prep")
      log "Manual: running session prep"
      run_claude "session-prep"
      notify_telegram "session-prep"
      ;;
    "day-plan")
      log "Manual: running day plan"
      run_claude "day-plan"
      notify_telegram "day-plan"
      ;;
    "note-review")
      run_note_review
      ;;
    "day-close")
      log "Manual: running day close"
      run_claude "day-close"
      notify_telegram "day-close"
      ;;
    "strategy-session")
      log "Manual: running strategy session (interactive)"
      run_claude "strategy-session"
      ;;
    *)
      echo "Usage: ${0} {morning|note-review|week-review|session-prep|strategy-session|day-plan|day-close}"
      echo ""
      echo "Scenarios:"
      echo "  morning           - 4:00 EET daily (session-prep on Mon, day-plan others)"
      echo "  note-review       - 23:00 EET daily (review fleeting notes + clean inbox)"
      echo "  week-review       - Sunday 19:00 EET review for club"
      echo "  session-prep      - Manual session prep (headless preparation)"
      echo "  strategy-session  - Manual strategy session (interactive with user)"
      echo "  day-plan          - Manual day plan"
      echo "  day-close         - Manual day close (update WeekPlan + MEMORY + backup)"
      exit 1
      ;;
  esac

  log "Done"
}

main "$@"
