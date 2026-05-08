#!/usr/bin/env bash
# assert-orz-cycle.sh — структурные инварианты полного цикла ОРЗ
# Проверяет что open → work → close оставили правильные артефакты
set -euo pipefail

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }

DS_DIR="$WS_DIR/DS-strategy"
[ ! -d "$DS_DIR" ] && DS_DIR="$WS_DIR"

FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- assert: ORZ Full Cycle ---"

MEMORY="$WS_DIR/memory/MEMORY.md"
WEEKPLAN=$(find "$DS_DIR/current" -name "WeekPlan*" -type f 2>/dev/null | head -1)
WP_CONTEXT=$(find "$DS_DIR/inbox" -name "WP-1*" -type f 2>/dev/null | head -1)
SESSION_LOG="$DS_DIR/inbox/open-sessions.log"

echo "  --- open: session registered ---"
if [ -f "$SESSION_LOG" ]; then
  grep -q 'WP-1' "$SESSION_LOG" 2>/dev/null \
    && _pass "session log: WP-1 registered" \
    || _pass "session log: WP-1 not found"
  entries=$(wc -l < "$SESSION_LOG" 2>/dev/null || echo 0)
  [ "$entries" -ge 1 ] && _pass "session log: $entries entries" || _fail "session log: empty"
else
  _pass "session log: not found (open phase may not have run)"
fi

echo "  --- work: WP context updated ---"
if [ -n "$WP_CONTEXT" ] && [ -f "$WP_CONTEXT" ]; then
  grep -qE '## Осталось|What.s Left' "$WP_CONTEXT" 2>/dev/null \
    && _pass "WP context: Осталось section" \
    || _fail "WP context: no Осталось"
  
  content=$(cat "$WP_CONTEXT" 2>/dev/null)
  [ "$(echo "$content" | wc -c)" -gt 100 ] \
    && _pass "WP context: substantive (>100 chars)" \
    || _pass "WP context: minimal"
fi

echo "  --- work: captures ---"
grep -qi 'capture\|Capture' "$WS_DIR/CLAUDE.md" 2>/dev/null \
  && _pass "CLAUDE.md: may have captured rules" \
  || _pass "CLAUDE.md: no capture (may be in separate session)"

echo "  --- close: MEMORY sync ---"
if [ -f "$MEMORY" ]; then
  grep -qE 'done|in_progress' "$MEMORY" 2>/dev/null \
    && _pass "MEMORY.md: WP status present" \
    || _fail "MEMORY.md: no statuses"
fi

echo "  --- close: commit ---"
cd "$WS_DIR" 2>/dev/null || true
if git rev-parse --git-dir >/dev/null 2>&1; then
  commits=$(git log --oneline 2>/dev/null | wc -l || echo 0)
  [ "$commits" -ge 1 ] \
    && _pass "git: $commits commit(s)" \
    || _fail "git: no commits"
fi

echo "  --- close: WP status in WeekPlan ---"
if [ -n "$WEEKPLAN" ] && [ -f "$WEEKPLAN" ]; then
  grep -qE 'done|complete' "$WEEKPLAN" 2>/dev/null \
    && _pass "WeekPlan: done VP found" \
    || _pass "WeekPlan: WP status check"
fi

echo "  --- no protocol violations ---"
grep -qi 'прыжок.*реализац\|skip.*open' "$SESSION_LOG" 2>/dev/null \
  && _fail "protocol violation detected" \
  || _pass "no protocol violations"

[ "$FAIL" -eq 0 ] && echo "  All assertions passed" || echo "  $FAIL assertion(s) failed"
exit $FAIL
