#!/usr/bin/env bash
# code-scan.sh — ночное сканирование Downstream-репо (статистика активности)
# Targets: Linux, macOS

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=lib/lib-env.sh
source "${SCRIPT_DIR}/../../../lib/lib-env.sh"

# shellcheck source=roles/synchronizer/lib/lib-code-scan.sh
source "${SCRIPT_DIR}/../lib/lib-code-scan.sh"

_repo_root="$(iwe_find_repo_root "${SCRIPT_DIR}")" \
  || { echo "ERROR: Cannot resolve repo root from ${SCRIPT_DIR}" >&2; exit 1; }
ENV_FILE="$(iwe_env_file_from_repo_root "${_repo_root}")"
unset _repo_root

iwe_load_env_file "$ENV_FILE" || exit 1
iwe_require_env_vars WORKSPACE_DIR || exit 1

WORKSPACE="$WORKSPACE_DIR"
LOG_DIR="$HOME/.local/state/logs/synchronizer"
DATE=$(date +%Y-%m-%d)
LOG_FILE="$LOG_DIR/code-scan-$DATE.log"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

mkdir -p "$LOG_DIR"

code_scan_log "$LOG_FILE" "=== Code Scan Started ==="
code_scan_run "$WORKSPACE" "$LOG_FILE" "$DRY_RUN"
code_scan_log "$LOG_FILE" "=== Code Scan Completed ==="

if [[ "$DRY_RUN" == "false" ]] && grep -q 'FOUND:' "$LOG_FILE" 2>/dev/null; then
  _NOTIFY_SH="${SCRIPT_DIR}/../../../scripts/notify.sh"
  _TMPL_DIR="${SCRIPT_DIR}/../../../scripts/templates"
  _MSG="$(bash -c 'source "$1"; build_message "code-scan"' _ "${_TMPL_DIR}/synchronizer.sh")" || true
  [[ -n "${_MSG}" ]] && "${_NOTIFY_SH}" "Code Scan" "${_MSG}" "notice" 2>/dev/null || true
  unset _NOTIFY_SH _TMPL_DIR _MSG
fi
