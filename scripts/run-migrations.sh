#!/usr/bin/env bash
# run-migrations.sh — запуск pending миграций в порядке версий
# Используется update.sh --apply перед обновлением файлов
# ADR-005 §4: миграции с версией > локальной И ≤ upstream

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MIGRATIONS_DIR="$ROOT_DIR/migrations"
LOG_FILE="$ROOT_DIR/.claude/logs/migrations.log"

APPLIED_MARKER="$ROOT_DIR/.claude/.migrations-applied"

mkdir -p "$(dirname "$LOG_FILE")"

# Determine which version threshold to use
# Default: apply all pending (no threshold = apply everything not yet applied)
LOCAL_VERSION="${1:-0.0.0}"
UPSTREAM_VERSION="${2:-999.999.999}"

_log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$1] run-migrations${2:+ — $2}" | tee -a "$LOG_FILE"; }

# Track which migrations we've already applied
declare -A applied
if [ -f "$APPLIED_MARKER" ]; then
  while IFS= read -r line; do
    applied["$line"]=1
  done < "$APPLIED_MARKER"
fi

compare_versions() {
  # Returns: -1 if $1 < $2, 1 if $1 > $2, 0 if equal
  local v1="${1#v}" v2="${2#v}"
  local IFS=.
  local i a b
  read -ra a <<< "$v1"
  read -ra b <<< "$v2"
  for i in 0 1 2; do
    local ai=$((10#${a[$i]:-0} 2>/dev/null || 0))
    local bi=$((10#${b[$i]:-0} 2>/dev/null || 0))
    [ "$ai" -lt "$bi" ] && echo "-1" && return
    [ "$ai" -gt "$bi" ] && echo "1" && return
  done
  echo "0"
}

_log "START" "local=$LOCAL_VERSION upstream=$UPSTREAM_VERSION"

RUN_COUNT=0
SKIP_COUNT=0

# Find all migration scripts, sorted by version
while IFS= read -r -d '' script; do
  name=$(basename "$script")
  [[ "$name" == "_template.sh" ]] && continue
  [[ "$name" == README.md ]] && continue
  [[ "$name" != *.sh ]] && continue

  ver="${name%%-*}"

  # Check: version > local AND version <= upstream?
  if [ "$(compare_versions "$ver" "$LOCAL_VERSION")" != "1" ]; then
    _log "SKIP" "$name (version $ver <= $LOCAL_VERSION)"
    SKIP_COUNT=$((SKIP_COUNT + 1))
    continue
  fi

  if [ "$(compare_versions "$ver" "$UPSTREAM_VERSION")" = "1" ]; then
    _log "SKIP" "$name (version $ver > upstream $UPSTREAM_VERSION)"
    SKIP_COUNT=$((SKIP_COUNT + 1))
    continue
  fi

  # Already applied?
  if [ -n "${applied[$name]:-}" ]; then
    _log "SKIP" "$name (already applied)"
    SKIP_COUNT=$((SKIP_COUNT + 1))
    continue
  fi

  # Run the migration
  _log "RUN" "$name"
  if bash "$script"; then
    echo "$name" >> "$APPLIED_MARKER"
    RUN_COUNT=$((RUN_COUNT + 1))
  else
    _log "FAIL" "$name exited non-zero"
    exit 1
  fi
done < <(find "$MIGRATIONS_DIR" -name "*.sh" -not -name "_template.sh" -print0 | sort -z)

_log "DONE" "ran=$RUN_COUNT skipped=$SKIP_COUNT"
echo "  Migrations: $RUN_COUNT applied, $SKIP_COUNT skipped"
