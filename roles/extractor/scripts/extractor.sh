#!/usr/bin/env bash
# Knowledge Extractor Agent Runner
# Запускает Claude Code с заданным процессом KE
# Targets: Linux, macOS
#
# Exit codes:
#   0 — успех
#   1 — ошибка (файл не найден, неверный аргумент)
#   2 — нет pending captures
#
set -euo pipefail

# Конфигурация
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=lib/lib-env.sh
source "${SCRIPT_DIR}/../../../lib/lib-env.sh"

# shellcheck source=roles/shared/lib/lib-notify.sh
source "${SCRIPT_DIR}/../../shared/lib/lib-notify.sh"

# shellcheck source=roles/shared/lib/lib-git-sync.sh
source "${SCRIPT_DIR}/../../shared/lib/lib-git-sync.sh"

# shellcheck source=roles/extractor/lib/lib-extractor-state.sh
source "${SCRIPT_DIR}/../lib/lib-extractor-state.sh"

# shellcheck source=roles/extractor/lib/lib-extractor-runner.sh
source "${SCRIPT_DIR}/../lib/lib-extractor-runner.sh"

_repo_root="$(iwe_find_repo_root "${SCRIPT_DIR}")" \
  || { echo "ERROR: Cannot resolve repo root from ${SCRIPT_DIR}" >&2; exit 1; }
ENV_FILE="$(iwe_env_file_from_repo_root "${_repo_root}")"
unset _repo_root

iwe_load_env_file "${ENV_FILE}" || exit 1
iwe_require_env_vars WORKSPACE_DIR CLAUDE_PATH || exit 1

WORKSPACE="$WORKSPACE_DIR"
PROMPTS_DIR="$REPO_DIR/prompts"
LOG_DIR="$HOME/.local/state/logs/extractor"

# AI CLI: переопределение через переменные окружения (см. strategist.sh)
AI_CLI="${AI_CLI:-$CLAUDE_PATH}"
AI_CLI_PROMPT_FLAG="${AI_CLI_PROMPT_FLAG:--p}"
AI_CLI_EXTRA_FLAGS="${AI_CLI_EXTRA_FLAGS:---dangerously-skip-permissions --allowedTools Read,Write,Edit,Glob,Grep,Bash}"

# Создаём папку для логов
mkdir -p "$LOG_DIR"

DATE=$(date +%Y-%m-%d)
HOUR=$(date +%H)
LOG_FILE="$LOG_DIR/$DATE.log"

notify_telegram() {
    local scenario="$1"
    local _notify_sh _tmpl_dir _msg
    _notify_sh="${SCRIPT_DIR}/../../../scripts/notify.sh"
    _tmpl_dir="${SCRIPT_DIR}/../../../scripts/templates"
    _msg="$(bash -c 'source "$1"; build_message "$2"' _ "${_tmpl_dir}/extractor.sh" "${scenario}")" || true
    [[ -z "${_msg}" ]] && return 0
    iwe_notify_via_script "${_notify_sh}" "KE: ${scenario}" "${_msg}" "notice" "${LOG_FILE}"
}

run_extractor_process() {
    local process_name="$1"
    local scenario="$2"

    extractor_run_process \
      "$process_name" \
      "$PROMPTS_DIR" \
      "$WORKSPACE" \
      "$AI_CLI" \
      "$AI_CLI_PROMPT_FLAG" \
      "$AI_CLI_EXTRA_FLAGS" \
      "$LOG_FILE"

    if iwe_sync_strategy_extraction_report "$WORKSPACE/DS-strategy" "$LOG_FILE" "$DATE"; then
        extractor_log "$LOG_FILE" "Synced DS-strategy extraction report"
    else
        extractor_log "$LOG_FILE" "WARN: DS-strategy sync failed"
    fi

    iwe_notify_local "KE: ${process_name}" "Процесс завершён"
    notify_telegram "$scenario"
}

# Определяем процесс
case "${1:-}" in
    "inbox-check")
        if ! extractor_is_work_hours; then
            extractor_log "$LOG_FILE" "SKIP: inbox-check outside work hours ($HOUR:00)"
            exit 0
        fi

        # Быстрая проверка: есть ли captures в inbox
        CAPTURES_FILE="$WORKSPACE/DS-strategy/inbox/captures.md"
        ACTUAL_PENDING="$(extractor_pending_captures_count "$CAPTURES_FILE")"
        if [ "$ACTUAL_PENDING" -lt 0 ]; then
            extractor_log "$LOG_FILE" "SKIP: captures.md not found"
            exit 0
        fi

        if [ "$ACTUAL_PENDING" -le 0 ]; then
            extractor_log "$LOG_FILE" "SKIP: No pending captures in inbox"
            exit 0
        fi

        extractor_log "$LOG_FILE" "Found $ACTUAL_PENDING pending captures in inbox"
        run_extractor_process "inbox-check" "inbox-check"
        ;;

    "audit")
        extractor_log "$LOG_FILE" "Running knowledge audit"
        run_extractor_process "knowledge-audit" "audit"
        ;;

    "session-close")
        extractor_log "$LOG_FILE" "Running session-close extraction"
        run_extractor_process "session-close" "session-close"
        ;;

    "on-demand")
        extractor_log "$LOG_FILE" "Running on-demand extraction"
        run_extractor_process "on-demand" "on-demand"
        ;;

    *)
        echo "Knowledge Extractor (R2)"
        echo ""
        echo "Usage: $0 <process>"
        echo ""
        echo "Processes:"
        echo "  inbox-check    Headless: обработка pending captures (launchd, 3h)"
        echo "  audit          Аудит Pack'ов"
        echo "  session-close  Экстракция при закрытии сессии"
        echo "  on-demand      Экстракция по запросу"
        exit 1
        ;;
esac

extractor_log "$LOG_FILE" "Done"
