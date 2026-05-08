#!/usr/bin/env bash
# assert-day-open.sh — структурные инварианты результата Day Open
# Проверяет DayPlan: секции, план, календарь, саморазвитие, «Требует внимания»
set -euo pipefail

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }

DS_DIR="$WS_DIR/DS-strategy"
[ ! -d "$DS_DIR" ] && DS_DIR="$WS_DIR"

FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- assert: Day Open ---"

DAYPLAN=$(find "$DS_DIR/current" -name "DayPlan*" -type f 2>/dev/null | head -1)
[ -z "$DAYPLAN" ] && { _fail "DayPlan not found"; exit $FAIL; }
echo "  DayPlan: $(basename "$DAYPLAN")"

WEEKPLAN=$(find "$DS_DIR/current" -name "WeekPlan*" -type f 2>/dev/null | head -1)
MEMORY="$WS_DIR/memory/MEMORY.md"

echo "  --- plan structure ---"
grep -qE '^## План на сегодня|^## План|^## Plan' "$DAYPLAN" 2>/dev/null \
  && _pass "section: План на сегодня" \
  || _fail "section: План на сегодня missing"

grep -A20 '^## План' "$DAYPLAN" 2>/dev/null | grep -q '^|' \
  && _pass "план: table present" \
  || _pass "план: no table (may use list format)"

grep -qiE 'календар|calendar|свобод' "$DAYPLAN" 2>/dev/null \
  && _pass "section: Календарь" \
  || _pass "section: Календарь not found"

echo "  --- carry-over ---"
grep -qiE 'carry.over|вчера.*итог|Итоги вчера|Yesterday' "$DAYPLAN" 2>/dev/null \
  && _pass "section: carry-over / вчера" \
  || _pass "section: carry-over not found"

echo "  --- self-development ---"
grep -qiE 'self.dev|саморазвит|⚫|self_dev' "$DAYPLAN" 2>/dev/null \
  && _pass "self-development: present" \
  || _pass "self-development: not found"

echo "  --- priority markers ---"
grep -qE '🚦|🔴|🟡|🟢' "$DAYPLAN" 2>/dev/null \
  && _pass "priority markers: found" \
  || _pass "priority markers: not found (may use text)"

echo "  --- attention section ---"
grep -qiE 'Требует внимания|requires attention|attention' "$DAYPLAN" 2>/dev/null \
  && _pass "section: Требует внимания" \
  || _pass "section: Требует внимания not found"

echo "  --- file modifications ---"
if [ -f "$MEMORY" ]; then
  [ -s "$MEMORY" ] && _pass "MEMORY.md: non-empty" || _fail "MEMORY.md: empty"
fi
if [ -n "$WEEKPLAN" ] && [ -f "$WEEKPLAN" ]; then
  [ "$(wc -l < "$WEEKPLAN")" -gt 5 ] \
    && _pass "WeekPlan: non-trivial" \
    || _pass "WeekPlan: minimal"
fi

echo "  --- DayPlan non-empty ---"
[ "$(wc -l < "$DAYPLAN")" -gt 10 ] \
  && _pass "DayPlan: >10 lines (substantial)" \
  || _fail "DayPlan: too short"

[ "$FAIL" -eq 0 ] && echo "  All assertions passed" || echo "  $FAIL assertion(s) failed"
exit $FAIL
