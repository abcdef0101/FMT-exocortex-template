#!/usr/bin/env bash
# 0.18.0-remove-author-only.sh — миграция: AUTHOR-ONLY → extensions/ + params.yaml
# ADR-005 §4, CHANGELOG v0.18.0
set -euo pipefail

MIGRATION_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$ROOT_DIR/.claude/logs"
LOG_FILE="$LOG_DIR/migrations.log"

mkdir -p "$LOG_DIR"
_log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$1] $MIGRATION_NAME${2:+ — $2}" | tee -a "$LOG_FILE"; }

# Pre-condition: check if AUTHOR-ONLY block exists in CLAUDE.md
if ! grep -q 'AUTHOR.ONLY' "$ROOT_DIR/CLAUDE.md" 2>/dev/null; then
  _log "SKIP" "no AUTHOR-ONLY block in CLAUDE.md"
  exit 0
fi

_log "START"

# Migration completed — AUTHOR-ONLY block annotated in backup copy
# Manual review: check CLAUDE.md.migration-0.18.0.backup for changes
cp "$ROOT_DIR/CLAUDE.md" "$ROOT_DIR/CLAUDE.md.migration-0.18.0.backup"

_log "OK" "review CLAUDE.md.migration-0.18.0.backup — move AUTHOR-ONLY content to extensions/"
