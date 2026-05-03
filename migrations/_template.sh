#!/usr/bin/env bash
# _template.sh — шаблон миграционного скрипта
# Копируй: cp _template.sh {version}-{component}-{description}.sh
# ADR-005 §4: идемпотентный, с backup, pre/post-conditions, логом
set -euo pipefail

MIGRATION_NAME="$(basename "$0")"
MIGRATION_VERSION="${MIGRATION_NAME%%-*}"  # extract version from filename prefix

# === Resolve directories ===
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$ROOT_DIR/.claude/logs"
LOG_FILE="$LOG_DIR/migrations.log"

mkdir -p "$LOG_DIR"

_log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$1] $MIGRATION_NAME${2:+ — $2}" | tee -a "$LOG_FILE"; }

# === Pre-condition: check if migration is needed ===
# TODO: Replace with actual pre-condition check
NEEDS_MIGRATION=true
# Example pre-condition:
# if [ -f "$ROOT_DIR/.claude/some-marker-file" ]; then
#   NEEDS_MIGRATION=false
# fi

if ! $NEEDS_MIGRATION; then
  _log "SKIP" "already applied"
  exit 0
fi

_log "START"

# === Backup ===
# TODO: Create backup of files before modifying
# cp "$ROOT_DIR/target-file" "$ROOT_DIR/target-file.backup" || {
#   _log "FAIL" "backup failed"
#   exit 1
# }

# === Apply ===
# TODO: Implement the actual migration
# Example:
# sed_inplace "s/old/new/g" "$ROOT_DIR/target-file"

# === Post-condition: validate ===
# TODO: Verify migration was applied correctly
# Example:
# if grep -q "new" "$ROOT_DIR/target-file"; then
#   _log "OK"
# else
#   _log "FAIL" "post-condition: expected 'new' not found"
#   exit 1
# fi

_log "OK"
