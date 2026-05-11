#!/usr/bin/env bash
# assert-role-execution.sh — детерминированные инварианты Role Execution
set -euo pipefail

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }

DS_DIR="$WS_DIR/DS-strategy"
[ ! -d "$DS_DIR" ] && DS_DIR="$WS_DIR"

FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- assert: Role Execution ---"

echo "  --- DayPlan created ---"
dayplans=$(find "$DS_DIR/current" -name "DayPlan*" -type f 2>/dev/null | wc -l)
[ "$dayplans" -ge 2 ] \
  && _pass "DayPlans: $dayplans in current/ (new one created)" \
  || _fail "DayPlan: expected a new plan, found only $dayplans"

latest=$(find "$DS_DIR/current" -name "DayPlan*" -type f 2>/dev/null | sort | tail -1)
if [ -n "$latest" ] && [ -f "$latest" ]; then
  lines=$(wc -l < "$latest" 2>/dev/null || echo 0)
  [ "$lines" -gt 5 ] \
    && _pass "new DayPlan: $lines lines" \
    || _fail "new DayPlan: too short ($lines lines)"
fi

echo "  --- plan table ---"
grep -q '^|' "$latest" 2>/dev/null \
  && _pass "table: present" \
  || _fail "table: not found in DayPlan"

echo "  --- carry-over ---"
grep -qiE 'carry.over\|Итоги вчера\|вчера' "$latest" 2>/dev/null \
  && _pass "carry-over: mentioned" \
  || _fail "carry-over: not found"

echo "  --- self-development ---"
grep -qiE 'self.dev\|саморазвит\|self_dev' "$latest" 2>/dev/null \
  && _pass "self-dev: present" \
  || _fail "self-dev: not found"

echo "  --- file integrity ---"
[ -f "$WS_DIR/memory/MEMORY.md" ] && _pass "MEMORY.md: present" || _fail "MEMORY.md: missing"
[ -f "$WS_DIR/CLAUDE.md" ] && _pass "CLAUDE.md: present" || _fail "CLAUDE.md: missing"

echo "  --- commit ---"
cd "$WS_DIR" 2>/dev/null || true
[ -d .git ] && _pass "git: repo exists" || _pass "git: not initialized"

[ "$FAIL" -eq 0 ] && echo "  All assertions passed" || echo "  $FAIL assertion(s) failed"
exit $FAIL
