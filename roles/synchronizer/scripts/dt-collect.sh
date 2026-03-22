#!/usr/bin/env bash
# dt-collect.sh — сбор данных активности для ЦД (WP-106)
# Targets: Linux, macOS
#
# Собирает: WakaTime + git stats + Claude Code sessions + WP stats
# Записывает в digital_twins.data JSONB (Neon) через dt-collect-neon.py
#
# Использование:
#   dt-collect.sh           # собрать и записать
#   dt-collect.sh --dry-run # показать JSON, не записывать
#
# Триггер: scheduler.sh dispatch dt-collect (ежедневно, после code-scan)
# Зависимости:
#   WAKATIME_API_KEY  — в ~/.config/aist/env
#   NEON_URL          — в ~/.config/aist/env (connection string)
#   DT_USER_ID        — в ~/.config/aist/env (Ory UUID)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=lib/lib-env.sh
source "${SCRIPT_DIR}/../../../lib/lib-env.sh"

# shellcheck source=lib/lib-platform.sh
source "${SCRIPT_DIR}/../../../lib/lib-platform.sh"

# shellcheck source=roles/synchronizer/lib/lib-dt-runtime.sh
source "${SCRIPT_DIR}/../lib/lib-dt-runtime.sh"

# shellcheck source=roles/synchronizer/lib/lib-dt-merge.sh
source "${SCRIPT_DIR}/../lib/lib-dt-merge.sh"

# shellcheck source=roles/synchronizer/lib/lib-dt-collectors.sh
source "${SCRIPT_DIR}/../lib/lib-dt-collectors.sh"

_repo_root="$(iwe_find_repo_root "${SCRIPT_DIR}")" \
  || { echo "ERROR: Cannot resolve repo root from ${SCRIPT_DIR}" >&2; exit 1; }
ENV_FILE="$(iwe_env_file_from_repo_root "${_repo_root}")"
unset _repo_root

iwe_load_env_file "${ENV_FILE}" || exit 1
iwe_require_env_vars WORKSPACE_DIR || exit 1

WORKSPACE="$WORKSPACE_DIR"
LOG_DIR="$HOME/.local/state/logs/synchronizer"
DATE=$(date +%Y-%m-%d)
LOG_FILE="$LOG_DIR/dt-collect-$DATE.log"

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

mkdir -p "$LOG_DIR"

ENV_FILE="$HOME/.config/aist/env"
dt_load_optional_aist_env || exit 1

dt_log "$LOG_FILE" "=== DT Collect Started ==="

# Проверка обязательных env vars (skip при --dry-run)
dt_check_write_prereqs "$DRY_RUN" "$LOG_FILE" || {
    status=$?
    if [[ "$status" -eq 10 || "$status" -eq 11 ]]; then
        exit 0
    fi
    exit "$status"
}

# ============================================================
# Merge & Write
# ============================================================

dt_log "$LOG_FILE" "Collecting WakaTime..."
WAKA_JSON=$(dt_collect_wakatime "$DATE")
dt_log "$LOG_FILE" "Collecting git stats..."
GIT_JSON=$(dt_collect_git "$WORKSPACE")
dt_log "$LOG_FILE" "Collecting Claude sessions..."
SESSIONS_JSON=$(dt_collect_sessions "$WORKSPACE/DS-strategy/inbox/open-sessions.log" "$WORKSPACE")
dt_log "$LOG_FILE" "Collecting WP stats..."
WP_JSON=$(dt_collect_wp "$HOME/.claude/projects/-Users-$(whoami)-IWE/memory/MEMORY.md")
dt_log "$LOG_FILE" "Collecting scheduler health..."
HEALTH_JSON=$(dt_collect_health "$HOME/.local/state/exocortex")

# Merge all into 2_6_coding + 2_7_iwe
MERGED=$(dt_merge_json_payload "$WAKA_JSON" "$GIT_JSON" "$SESSIONS_JSON" "$WP_JSON" "$HEALTH_JSON")

if [ -z "$MERGED" ] || [ "$MERGED" = "{}" ]; then
    dt_log "$LOG_FILE" "ERROR: empty merge result"
    exit 1
fi

dt_log "$LOG_FILE" "Merged JSON:"
echo "$MERGED" >> "$LOG_FILE"

if [ "$DRY_RUN" = true ]; then
    echo "$MERGED"
    dt_log "$LOG_FILE" "DRY RUN — not writing to Neon"
    exit 0
fi

# Write to Neon
if dt_write_payload "$SCRIPT_DIR" "$DT_USER_ID" "$MERGED" "$LOG_FILE"; then
    dt_log "$LOG_FILE" "=== DT Collect Completed Successfully ==="
    _NOTIFY_SH="${SCRIPT_DIR}/../../../scripts/notify.sh"
    _TMPL_DIR="${SCRIPT_DIR}/../../../scripts/templates"
    _MSG="$(bash -c 'source "$1"; build_message "dt-collect"' _ "${_TMPL_DIR}/synchronizer.sh")" || true
    [[ -n "${_MSG}" ]] && "${_NOTIFY_SH}" "DT Collect" "${_MSG}" "notice" 2>/dev/null || true
    unset _NOTIFY_SH _TMPL_DIR _MSG
else
    EXIT_CODE=$?
    dt_log "$LOG_FILE" "ERROR: dt-collect-neon.py exited with $EXIT_CODE"
    exit "$EXIT_CODE"
fi
