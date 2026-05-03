#!/usr/bin/env bash
# Миграция: DayPlan требует <details> collapsible
# CHANGELOG v0.24.0
set -euo pipefail
MIGRATION_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$ROOT_DIR/.claude/logs"
LOG_FILE="$LOG_DIR/migrations.log"
mkdir -p "$LOG_DIR"
_log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$1] $MIGRATION_NAME${2:+ — $2}" | tee -a "$LOG_FILE"; }

_log "START"
_log "INFO" "DayPlan <details> format is enforced by day-open skill (v2.0.0+)"
_log "INFO" "Manual step: wrap WP-* blocks in <details><summary>...</summary></details>"
_log "INFO" "Example: <details><summary>WP-001 Task name</summary>content</details>"
_log "OK" "documented migration — apply manually if needed"
