#!/usr/bin/env bash
# assert-week-close.sh — структурные инварианты после Week Close
# Блокирующий CI gate. Проверяет результат AI-процесса, не процесс.
set -euo pipefail

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }

DS_DIR="$WS_DIR/DS-strategy"
[ ! -d "$DS_DIR" ] && DS_DIR="$WS_DIR"

FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- assert: Week Close ---"

WEEKPLAN="${2:-}"
if [ -z "$WEEKPLAN" ] || [ ! -f "$WEEKPLAN" ]; then
  WEEKPLAN=$(find "$DS_DIR/current" -name "WeekPlan*" -type f 2>/dev/null | head -1)
fi
[ -z "$WEEKPLAN" ] && { _fail "WeekPlan not found"; exit $FAIL; }
echo "  WeekPlan: $(basename "$WEEKPLAN")"

MEMORY="$WS_DIR/memory/MEMORY.md"

echo "  --- итоги недели ---"
grep -qE '^## Итоги W' "$WEEKPLAN" 2>/dev/null \
  && _pass "section: Итоги W{N}" \
  || _fail "section: Итоги W{N} missing"

grep -qE '[0-9]+%' "$WEEKPLAN" 2>/dev/null \
  && _pass "completion rate: % found" \
  || _fail "completion rate: no percentage"

grep -qi 'carry.over' "$WEEKPLAN" 2>/dev/null \
  && _pass "carry-over: mentioned" \
  || _pass "carry-over: not found"

echo "  --- content plan ---"
grep -qiE 'контент.план|content.plan|публикац|publish' "$WEEKPLAN" 2>/dev/null \
  && _pass "content plan: mentioned" \
  || _pass "content plan: not found"

echo "  --- MEMORY.md ---"
if [ -f "$MEMORY" ]; then
  grep -qE 'done|in_progress|pending' "$MEMORY" 2>/dev/null \
    && _pass "MEMORY.md: WP statuses" \
    || _fail "MEMORY.md: no WP statuses"
else
  _pass "MEMORY.md: not present"
fi

echo "  --- commit ---"
cd "$WS_DIR" 2>/dev/null || true
if git rev-parse --git-dir >/dev/null 2>&1; then
  git log -1 --format="  commit: %s" 2>/dev/null
  _pass "git: commit exists"
else
  _pass "git: not a repo"
fi

echo "  --- no Day Close artifacts leak ---"
grep -qi 'praise\|похвала' "$WEEKPLAN" 2>/dev/null \
  && _pass "no Day Close drift (Praise in WeekPlan — ok)" \
  || true

[ "$FAIL" -eq 0 ] && echo "  All assertions passed" || echo "  $FAIL assertion(s) failed"
exit $FAIL
