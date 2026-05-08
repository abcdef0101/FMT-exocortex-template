#!/usr/bin/env bash
# assert-day-close.sh — структурные инварианты после Day Close
# Блокирующий CI gate. Проверяет результат AI-процесса, не процесс.
# Usage: bash scripts/test/assert-day-close.sh <workspace_dir> [DayPlan_path]
set -euo pipefail

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }
[ ! -d "$WS_DIR" ] && { echo "ERROR: dir not found: $WS_DIR" >&2; exit 1; }

DS_DIR="$WS_DIR/DS-strategy"
[ ! -d "$DS_DIR" ] && DS_DIR="$WS_DIR"  # fallback: workspace root

FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- assert: Day Close ---"

# Find DayPlan (given or auto-detect)
DAYPLAN="${2:-}"
if [ -z "$DAYPLAN" ] || [ ! -f "$DAYPLAN" ]; then
  DAYPLAN=$(find "$DS_DIR/current" -name "Day*Plan*" -type f 2>/dev/null | head -1)
fi
[ -z "$DAYPLAN" ] && { _fail "DayPlan not found"; exit $FAIL; }
echo "  DayPlan: $(basename "$DAYPLAN")"

WEEKPLAN=$(find "$DS_DIR/current" -name "WeekPlan*" -type f 2>/dev/null | head -1)
MEMORY="$WS_DIR/memory/MEMORY.md"
REGISTRY=$(find "$DS_DIR/docs" -name "WP-REGISTRY*" -type f 2>/dev/null | head -1)

echo "  --- итоги дня ---"
grep -qE '^## Итоги|^## Итоги дня' "$DAYPLAN" 2>/dev/null \
  && _pass "section: Итоги дня" \
  || _fail "section: Итоги дня missing"

grep -A30 '^## Итоги' "$DAYPLAN" 2>/dev/null | grep -q '^|' \
  && _pass "итоги: table present" \
  || _fail "итоги: no table found"

row_count=$(grep -A30 '^## Итоги' "$DAYPLAN" 2>/dev/null | grep -cE '^\|.*\|.*\|.*\|' 2>/dev/null || echo 0)
[ "$row_count" -ge 2 ] \
  && _pass "итоги: $row_count data rows" \
  || _fail "итоги: only $row_count rows (expected ≥2)"

echo "  --- multiplier ---"
grep -qi 'multiplier' "$DAYPLAN" 2>/dev/null \
  && _pass "multiplier: mentioned" \
  || _fail "multiplier: not found"

echo "  --- praise + tomorrow ---"
grep -qE '^## Praise|^## Похвала' "$DAYPLAN" 2>/dev/null \
  && _pass "section: Praise" \
  || _pass "section: Praise not present (optional)"

grep -qE 'Завтра начать с|Next Day Start' "$DAYPLAN" 2>/dev/null \
  && _pass "section: Завтра начать с" \
  || _fail "section: Завтра начать с missing"

echo "  --- file modifications ---"
if [ -f "$MEMORY" ]; then
  grep -qE 'done|not started' "$MEMORY" 2>/dev/null \
    && _pass "MEMORY.md: statuses present" \
    || _pass "MEMORY.md: check status format"
else
  _pass "MEMORY.md: not present (workspace not fully set up)"
fi

if [ -n "$WEEKPLAN" ] && [ -f "$WEEKPLAN" ]; then
  lines=$(wc -l < "$WEEKPLAN")
  [ "$lines" -gt 10 ] \
    && _pass "WeekPlan: $lines lines" \
    || _fail "WeekPlan: unexpectedly short ($lines lines)"
fi

echo "  --- commit ---"
cd "$WS_DIR" 2>/dev/null || true
if git rev-parse --git-dir >/dev/null 2>&1; then
  git log -1 --format="  commit: %s" 2>/dev/null
  _pass "git: commit exists"
else
  _pass "git: not a repo (seed without git)"
fi

echo "  --- no stale temps ---"
stale=$(find "$WS_DIR" -name "*.tmp" -o -name "*.temp" 2>/dev/null | head -5 || true)
[ -z "$stale" ] \
  && _pass "no stale temp files" \
  || _fail "stale temp files found: $stale"

[ "$FAIL" -eq 0 ] && echo "  All assertions passed" || echo "  $FAIL assertion(s) failed"
exit $FAIL
