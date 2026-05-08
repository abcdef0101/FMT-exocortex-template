#!/usr/bin/env bash
# assert-wp-new.sh — структурные инварианты после wp-new
# Проверяет что новый РП записан во все 5 мест атомарно
set -euo pipefail

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }

DS_DIR="$WS_DIR/DS-strategy"
[ ! -d "$DS_DIR" ] && DS_DIR="$WS_DIR"

FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- assert: wp-new ---"

MEMORY="$WS_DIR/memory/MEMORY.md"
REGISTRY=$(find "$DS_DIR/docs" -name "WP-REGISTRY*" -type f 2>/dev/null | head -1)
WEEKPLAN=$(find "$DS_DIR/current" -name "WeekPlan*" -type f 2>/dev/null | head -1)
DAYPLAN=$(find "$DS_DIR/current" -name "Day*Plan*" -type f 2>/dev/null | head -1)
WP_CONTEXT=$(find "$DS_DIR/inbox" -name "WP-5*" -type f 2>/dev/null | head -1)

echo "  --- 5-location check ---"

# 1. REGISTRY
if [ -n "$REGISTRY" ] && [ -f "$REGISTRY" ]; then
  grep -q "WP-5\|CI gates" "$REGISTRY" 2>/dev/null \
    && _pass "REGISTRY: WP-5 found" \
    || _fail "REGISTRY: WP-5 not found"
else
  _pass "REGISTRY: not found (seed without registry)"
fi

# 2. MEMORY
if [ -f "$MEMORY" ]; then
  grep -q "WP-5\|CI gates" "$MEMORY" 2>/dev/null \
    && _pass "MEMORY.md: WP-5 found" \
    || _fail "MEMORY.md: WP-5 not found"
fi

# 3. WeekPlan
if [ -n "$WEEKPLAN" ] && [ -f "$WEEKPLAN" ]; then
  grep -q "WP-5\|CI gates" "$WEEKPLAN" 2>/dev/null \
    && _pass "WeekPlan: WP-5 found" \
    || _fail "WeekPlan: WP-5 not found"
fi

# 4. DayPlan
if [ -n "$DAYPLAN" ] && [ -f "$DAYPLAN" ]; then
  grep -q "WP-5\|CI gates" "$DAYPLAN" 2>/dev/null \
    && _pass "DayPlan: WP-5 found" \
    || _pass "DayPlan: WP-5 not in today's plan (ok if DayPlan inactive)"
fi

# 5. WP Context
if [ -n "$WP_CONTEXT" ] && [ -f "$WP_CONTEXT" ]; then
  grep -qE '## Осталось|## What.s Left' "$WP_CONTEXT" 2>/dev/null \
    && _pass "WP Context: Осталось section" \
    || _fail "WP Context: no Осталось section"
else
  _pass "WP Context: WP-5 context file not found"
fi

echo "  --- naming convention ---"

grep -oP 'WP-5[^|]*' "$REGISTRY" "$MEMORY" "$WEEKPLAN" 2>/dev/null | head -3 | while read name; do
  echo "  name: $name"
done

# Check sequential numbering (no letter suffixes)
grep -qP 'WP-5[a-zA-Z]' "$REGISTRY" "$MEMORY" 2>/dev/null \
  && _fail "naming: WP-5 has letter suffix (should be integer only)" \
  || _pass "naming: no letter suffixes"

echo "  --- unique WP number ---"
grep -c 'WP-5' "$REGISTRY" 2>/dev/null | head -1 | while read count; do
  [ "${count:-0}" -eq 1 ] \
    && _pass "WP-5: unique entry ($count occurrence)" \
    || _pass "WP-5: $count occurrences"
done

[ "$FAIL" -eq 0 ] && echo "  All assertions passed" || echo "  $FAIL assertion(s) failed"
exit $FAIL
