#!/usr/bin/env bash
# daily-report.sh — ежедневный отчёт работы scheduler
# Targets: Linux, macOS
#
# Формирует отчёт: что должно было сработать, что сработало, что нет.
# Результат: DS-strategy/current/SchedulerReport YYYY-MM-DD.md
#
# Использование:
#   daily-report.sh           # сформировать отчёт за сегодня
#   daily-report.sh --dry-run # показать отчёт, не записывать

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=lib/lib-env.sh
source "${SCRIPT_DIR}/../../../lib/lib-env.sh"

# shellcheck source=roles/synchronizer/lib/lib-daily-report-state.sh
source "${SCRIPT_DIR}/../lib/lib-daily-report-state.sh"

# shellcheck source=roles/synchronizer/lib/lib-daily-report-render.sh
source "${SCRIPT_DIR}/../lib/lib-daily-report-render.sh"

_repo_root="$(iwe_find_repo_root "${SCRIPT_DIR}")" \
  || { echo "ERROR: Cannot resolve repo root from ${SCRIPT_DIR}" >&2; exit 1; }
ENV_FILE="$(iwe_env_file_from_repo_root "${_repo_root}")"
unset _repo_root

iwe_load_env_file "${ENV_FILE}" || exit 1
iwe_require_env_vars WORKSPACE_DIR || exit 1

STATE_DIR="$HOME/.local/state/exocortex"
LOG_DIR="$HOME/.local/state/logs/synchronizer"
STRATEGY_DIR="$WORKSPACE_DIR/DS-strategy"
REPORT_DIR="$STRATEGY_DIR/current"
ARCHIVE_DIR="$STRATEGY_DIR/archive/scheduler-reports"

DATE=$(date +%Y-%m-%d)
DOW=$(date +%u)
HOUR=$(date +%H)
WEEK=$(date +%V)
NOW_EPOCH=$(date +%s)

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

REPORT_FILE="$REPORT_DIR/SchedulerReport $DATE.md"
SCHEDULER_LOG="$LOG_DIR/scheduler-$DATE.log"

mkdir -p "$ARCHIVE_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [daily-report] $1"
}

log "=== Daily Report Started ==="

REPORT="$(daily_report_generate "$STATE_DIR" "$SCHEDULER_LOG" "$DATE" "$DOW" "$HOUR" "$WEEK" "$NOW_EPOCH" "$WORKSPACE_DIR")"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "$REPORT"
  log "DRY RUN — отчёт не записан"
else
  echo "$REPORT" > "$REPORT_FILE"
  log "Report written: $REPORT_FILE"

  cd "$STRATEGY_DIR"
  git pull --rebase --quiet 2>/dev/null || log "WARN: pull --rebase failed (offline?)"
  git reset --quiet 2>/dev/null || true

  daily_report_archive_old_reports "$REPORT_DIR" "$ARCHIVE_DIR" "$DATE" log

  git add "current/SchedulerReport"*.md 2>/dev/null || true
  git add "archive/scheduler-reports/" 2>/dev/null || true

  if ! git diff --cached --quiet 2>/dev/null; then
    git commit -m "auto: scheduler report $DATE" --quiet
    git push --quiet 2>/dev/null || log "WARN: push failed"
    log "Committed and pushed"
  else
    log "No changes to commit"
  fi
fi

log "=== Daily Report Completed ==="
