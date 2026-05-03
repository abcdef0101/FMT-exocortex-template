#!/usr/bin/env bash
# Миграция: проверка/восстановление persistent-memory symlink
# ADR-004 criterion 5, ADR-005 §4 Risks
set -euo pipefail
MIGRATION_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$ROOT_DIR/.claude/logs"
LOG_FILE="$LOG_DIR/migrations.log"
mkdir -p "$LOG_DIR"
_log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$1] $MIGRATION_NAME${2:+ — $2}" | tee -a "$LOG_FILE"; }

# Find workspace
WS_LINK="$ROOT_DIR/workspaces/CURRENT_WORKSPACE"
WS_DIR=""
if [ -L "$WS_LINK" ]; then
  WS_DIR="$(cd "$(dirname "$WS_LINK")" && cd "$(readlink "$WS_LINK")" && pwd)"
elif [ -d "$WS_LINK" ]; then
  WS_DIR="$WS_LINK"
fi

if [ -z "$WS_DIR" ]; then
  _log "SKIP" "no workspace found"
  exit 0
fi

SYMLINK="$WS_DIR/memory/persistent-memory"

if [ -L "$SYMLINK" ] && [ -e "$SYMLINK" ]; then
  _log "SKIP" "symlink already valid"
  exit 0
fi

_log "START" "fixing persistent-memory symlink"

if [ -L "$SYMLINK" ]; then
  rm -f "$SYMLINK"
elif [ -e "$SYMLINK" ]; then
  cp -r "$SYMLINK" "${SYMLINK}.backup"
  rm -rf "$SYMLINK"
fi

ln -s "../../../persistent-memory/" "$SYMLINK"

if [ -L "$SYMLINK" ] && [ -e "$SYMLINK" ]; then
  _log "OK" "symlink restored"
else
  _log "FAIL" "symlink still broken after repair"
  exit 1
fi
