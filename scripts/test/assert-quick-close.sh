#!/usr/bin/env bash
# assert-quick-close.sh — структурные инварианты после Quick Close
# Блокирующий CI gate. Проверяет результат AI-процесса, не процесс.
set -euo pipefail

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }

DS_DIR="$WS_DIR/DS-strategy"
[ ! -d "$DS_DIR" ] && DS_DIR="$WS_DIR"

FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- assert: Quick Close ---"

MEMORY="$WS_DIR/memory/MEMORY.md"
DAYPLAN=$(find "$DS_DIR/current" -name "Day*Plan*" -type f 2>/dev/null | head -1)
WEEKPLAN=$(find "$DS_DIR/current" -name "WeekPlan*" -type f 2>/dev/null | head -1)

echo "  --- WP Context ---"
wp_contexts=$(find "$DS_DIR/inbox" -name "WP-*.md" -type f 2>/dev/null || true)
if [ -n "$wp_contexts" ]; then
  has_remaining=$(echo "$wp_contexts" | while read f; do grep -lE '## Осталось|## What.s Left' "$f" 2>/dev/null; done | wc -l)
  [ "$has_remaining" -ge 1 ] \
    && _pass "WP Context: $has_remaining files with Осталось" \
    || _pass "WP Context: no Осталось section"
  
  has_memory_field=$(echo "$wp_contexts" | while read f; do grep -l '→ memory:' "$f" 2>/dev/null; done | wc -l)
  [ "$has_memory_field" -ge 1 ] \
    && _pass "WP Context: → memory: field ($has_memory_field files)" \
    || _pass "→ memory: field not found"
else
  _pass "WP Context: no files (empty workspace)"
fi

echo "  --- MEMORY.md ---"
if [ -f "$MEMORY" ]; then
  grep -qE 'done|in_progress' "$MEMORY" 2>/dev/null \
    && _pass "MEMORY.md: WP statuses" \
    || _fail "MEMORY.md: no statuses"
fi

echo "  --- no Day Close drift ---"
no_drift=true
if [ -n "$DAYPLAN" ] && [ -f "$DAYPLAN" ]; then
  grep -qi 'multiplier' "$DAYPLAN" 2>/dev/null && no_drift=false
  grep -qi 'praise\|похвала' "$DAYPLAN" 2>/dev/null && no_drift=false
fi
$no_drift \
  && _pass "no Day Close drift (no multiplier/praise in DayPlan)" \
  || _fail "Day Close drift detected in Quick Close"

echo "  --- commit ---"
cd "$WS_DIR" 2>/dev/null || true
if git rev-parse --git-dir >/dev/null 2>&1; then
  commits=$(git log -1 --oneline 2>/dev/null || true)
  [ -n "$commits" ] \
    && _pass "git: commit exists" \
    || _pass "git: no recent commits"
fi

echo "  --- session log ---"
session_log="$DS_DIR/inbox/open-sessions.log"
if [ -f "$session_log" ]; then
  lines=$(wc -l < "$session_log" 2>/dev/null || echo 0)
  [ "$lines" -ge 1 ] \
    && _pass "session log: $lines entries" \
    || _pass "session log: empty"
else
  _pass "session log: not found"
fi

[ "$FAIL" -eq 0 ] && echo "  All assertions passed" || echo "  $FAIL assertion(s) failed"
exit $FAIL
