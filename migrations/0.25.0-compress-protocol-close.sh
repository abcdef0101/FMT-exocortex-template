#!/usr/bin/env bash
# Миграция: сжатие protocol-close.md (454 → 97 строк)
# Реальная миграция не нужна: файл обновляется через update.sh checksum-apply
# Этот скрипт документирует breaking change для пользователей с кастомизациями
set -euo pipefail
MIGRATION_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$ROOT_DIR/.claude/logs"
LOG_FILE="$LOG_DIR/migrations.log"
mkdir -p "$LOG_DIR"
_log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$1] $MIGRATION_NAME${2:+ — $2}" | tee -a "$LOG_FILE"; }

PROTOCOL="$ROOT_DIR/persistent-memory/protocol-close.md"
if [ ! -f "$PROTOCOL" ]; then
  _log "SKIP" "protocol-close.md not found"
  exit 0
fi

OLD_LINES=$(wc -l < "$PROTOCOL")
if [ "$OLD_LINES" -le 100 ]; then
  _log "SKIP" "already compressed ($OLD_LINES lines)"
  exit 0
fi

_log "START" "protocol-close.md has $OLD_LINES lines"
_log "INFO" "protocol-close.md will be updated via update.sh checksum-apply"
_log "INFO" "if you customized protocol-close.md, backup is at protocol-close.md.backup"
cp "$PROTOCOL" "${PROTOCOL}.backup"
_log "OK" "backup saved"
