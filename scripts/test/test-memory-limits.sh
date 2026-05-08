#!/usr/bin/env bash
# test-memory-limits.sh — проверка лимитов памяти (§2 Memory, workflow-full.md)
#   ≤11 файлов в persistent-memory/
#   Справочники: ≤100 строк
#   Протоколы: ≤150 строк
#   MEMORY.md: ≤100 строк
# По умолчанию — advisory (warning). --strict — блокирующий.
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
PM_DIR="$ROOT_DIR/persistent-memory"
WS_DIR="${WORKSPACE_DIR:-$ROOT_DIR/workspaces/CURRENT_WORKSPACE}"
if [ -L "$WS_DIR" ]; then
  WS_DIR=$(cd "$WS_DIR" && pwd -P 2>/dev/null || python3 -c "import os; print(os.path.realpath('$WS_DIR'))" 2>/dev/null || echo "$WS_DIR")
fi
MEMORY_MD="${MEMORY_MD:-$WS_DIR/memory/MEMORY.md}"

STRICT=false
for arg in "$@"; do [[ "$arg" == "--strict" ]] && STRICT=true; done

FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
_warn() { echo "  ! $1"; }

echo "  --- persistent-memory file count (limit: ≤11) ---"

if [ ! -d "$PM_DIR" ]; then
  _fail "persistent-memory directory not found"
  exit $FAIL
fi

pm_count=$(find "$PM_DIR" -maxdepth 1 -name "*.md" -type f | wc -l)
if [ "$pm_count" -le 11 ]; then
  _pass "persistent-memory: $pm_count files (limit: 11)"
else
  _fail "persistent-memory: $pm_count files (limit: 11)"
fi

echo "  --- reference files (limit: ≤100 lines) ---"
ref_violations=0
for f in "$PM_DIR"/fpf-reference.md "$PM_DIR"/sota-reference.md "$PM_DIR"/roles.md "$PM_DIR"/navigation.md "$PM_DIR"/checklists.md "$PM_DIR"/repo-type-rules.md; do
  [ ! -f "$f" ] && continue
  name=$(basename "$f")
  lines=$(wc -l < "$f")
  if [ "$lines" -le 100 ]; then
    _pass "$name: $lines lines (limit: 100)"
  else
    ref_violations=$((ref_violations + 1))
    if $STRICT; then
      _fail "$name: $lines lines (limit: 100)"
    else
      _warn "$name: $lines lines (limit: 100) — advisory"
    fi
  fi
done
if ! $STRICT && [ "$ref_violations" -gt 0 ]; then
  echo "  (advisory: $ref_violations reference file(s) exceed 100 lines — use --strict to block)"
fi

echo "  --- hard-distinctions.md (special: ≤100 lines guideline) ---"
if [ -f "$PM_DIR/hard-distinctions.md" ]; then
  hd_lines=$(wc -l < "$PM_DIR/hard-distinctions.md")
  if [ "$hd_lines" -le 100 ]; then
    _pass "hard-distinctions.md: $hd_lines lines (guideline: 100)"
  elif $STRICT; then
    _fail "hard-distinctions.md: $hd_lines lines (guideline: 100)"
  else
    _warn "hard-distinctions.md: $hd_lines lines (guideline: 100) — advisory, ≥50 distinctions"
  fi
fi

echo "  --- protocol files (limit: ≤150 lines) ---"
proto_violations=0
for f in "$PM_DIR"/protocol-open.md "$PM_DIR"/protocol-work.md "$PM_DIR"/protocol-close.md; do
  [ ! -f "$f" ] && continue
  name=$(basename "$f")
  lines=$(wc -l < "$f")
  if [ "$lines" -le 150 ]; then
    _pass "$name: $lines lines (limit: 150)"
  else
    proto_violations=$((proto_violations + 1))
    if $STRICT; then
      _fail "$name: $lines lines (limit: 150)"
    else
      _warn "$name: $lines lines (limit: 150) — advisory"
    fi
  fi
done
if ! $STRICT && [ "$proto_violations" -gt 0 ]; then
  echo "  (advisory: $proto_violations protocol(s) exceed 150 lines — use --strict to block)"
fi

echo "  --- templates-dayplan.md (special: ≤100 lines guideline) ---"
if [ -f "$PM_DIR/templates-dayplan.md" ]; then
  td_lines=$(wc -l < "$PM_DIR/templates-dayplan.md")
  if [ "$td_lines" -le 100 ]; then
    _pass "templates-dayplan.md: $td_lines lines (guideline: 100)"
  elif $STRICT; then
    _fail "templates-dayplan.md: $td_lines lines (guideline: 100)"
  else
    _warn "templates-dayplan.md: $td_lines lines (guideline: 100) — advisory"
  fi
fi

echo "  --- MEMORY.md (limit: ≤100 lines) ---"
if [ -f "$MEMORY_MD" ]; then
  mem_lines=$(wc -l < "$MEMORY_MD")
  if [ "$mem_lines" -le 100 ]; then
    _pass "MEMORY.md: $mem_lines lines (limit: 100)"
  else
    _fail "MEMORY.md: $mem_lines lines (limit: 100)"
  fi
else
  _pass "MEMORY.md: not found (workspace not set up)"
fi

echo "  --- memory/ directory limit (≤11 files) ---"
if [ -d "$WS_DIR/memory" ]; then
  ws_mem_count=$(find "$WS_DIR/memory" -maxdepth 1 -name "*.md" -type f | wc -l)
  if [ "$ws_mem_count" -le 11 ]; then
    _pass "workspace memory: $ws_mem_count files (limit: 11)"
  else
    _fail "workspace memory: $ws_mem_count files (limit: 11)"
  fi
fi

# -------------------------------------------------------------------
if $STRICT; then
  [ "$FAIL" -eq 0 ] && echo "  All checks passed (strict mode)" || echo "  $FAIL check(s) failed (strict mode)"
else
  echo "  $FAIL failure(s), $(($ref_violations + $proto_violations)) advisory warning(s)"
fi
exit $FAIL
