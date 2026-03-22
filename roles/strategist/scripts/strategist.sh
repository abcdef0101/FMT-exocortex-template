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

# shellcheck source=lib/lib-env.sh
source "${SCRIPT_DIR}/../../../lib/lib-env.sh"

# shellcheck source=roles/shared/lib/lib-notify.sh
source "${SCRIPT_DIR}/../../shared/lib/lib-notify.sh"

# shellcheck source=roles/shared/lib/lib-lock.sh
source "${SCRIPT_DIR}/../../shared/lib/lib-lock.sh"

# shellcheck source=roles/strategist/lib/lib-strategist-context.sh
source "${SCRIPT_DIR}/../lib/lib-strategist-context.sh"

# shellcheck source=roles/strategist/lib/lib-strategist-runner.sh
source "${SCRIPT_DIR}/../lib/lib-strategist-runner.sh"

_repo_root="$(iwe_find_repo_root "${SCRIPT_DIR}")" \
  || { echo "ERROR: Cannot resolve repo root from ${SCRIPT_DIR}" >&2; exit 1; }
_iwe_ws="$(iwe_workspace_dir_from_repo_root "${_repo_root}")"
ENV_FILE="$(iwe_env_file_from_repo_root "${_repo_root}")"
readonly ENV_FILE
_ws_slug="$(iwe_project_slug_from_workspace "${_iwe_ws}")"
RHYTHM_CONFIG="${HOME}/.claude/projects/${_ws_slug}/memory/day-rhythm-config.yaml"
readonly RHYTHM_CONFIG
unset _repo_root _iwe_ws _ws_slug

iwe_load_env_file "${ENV_FILE}" || exit 1

# Guard: required env vars must be set (fail-fast after sourcing)
iwe_require_env_vars WORKSPACE_DIR CLAUDE_PATH || exit 1

# Guard: python3 required for date localisation and JSON encoding
strategist_python_required || { echo "ERROR: python3 is required but not found" >&2; exit 1; }

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
  iwe_notify_local "${1}" "${2}"
}

function notify_telegram() {
  local scenario="${1}"
  local _notify_sh _tmpl_dir _msg
  _notify_sh="$(dirname "$(dirname "$(dirname "${SCRIPT_DIR}")")")/scripts/notify.sh"
  _tmpl_dir="${SCRIPT_DIR}/templates"
  _msg="$(bash -c 'source "$1"; build_message "$2"' _ "${_tmpl_dir}/strategist.sh" "${scenario}")" || true
  [[ -z "${_msg}" ]] && return 0
  "${_notify_sh}" "Стратег: ${scenario}" "${_msg}" "notice" >> "${LOG_FILE}" 2>&1 || true
}

function run_claude() {
  strategist_run_scenario "${1}" "${PROMPTS_DIR}" "${WORKSPACE}" "${CLAUDE_PATH}" "${LOG_FILE}" "${DATE}" "${DAY_OF_WEEK}" log notify
}

# Проверка: уже запускался ли сценарий сегодня
function already_ran_today() {
  strategist_already_ran_today "${LOG_FILE}" "${1}"
}

# File-based lock to prevent concurrent execution (RunAtLoad + CalendarInterval race)
readonly LOCK_DIR="${LOG_DIR}/locks"
mkdir -p "${LOCK_DIR}"
iwe_register_lock_cleanup_trap

function acquire_lock() {
  local scenario="${1}"
  iwe_acquire_symlink_lock "${LOCK_DIR}" "${scenario}.${DATE}" log || exit "$?"
}

# Читаем strategy_day из конфига (L4 Personal)
STRATEGY_DAY_NAME=$(strategist_read_strategy_day_name "${RHYTHM_CONFIG}")
readonly STRATEGY_DAY_NAME
STRATEGY_DAY_NUM=$(strategist_day_name_to_num "${STRATEGY_DAY_NAME}")
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
    local alert_text
    alert_text="⚠️ <b>Note-Review canary</b>: Step 10 не сработал (${bold_new_before} → ${bold_new_after} new bold). Deterministic cleanup applied."
    "$(dirname "$(dirname "$(dirname "${SCRIPT_DIR}")")")/scripts/notify.sh" \
      "Note-Review canary" "${alert_text}" "alert" >> "${LOG_FILE}" 2>&1 || true
  fi

  notify_telegram "note-review"
}

function main() {
  local scenario
  case "${1:-}" in
    "morning")
      scenario="$(strategist_resolve_morning_scenario "${DAY_OF_WEEK}" "${STRATEGY_DAY_NUM}")"

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
