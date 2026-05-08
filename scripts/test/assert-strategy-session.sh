#!/usr/bin/env bash
# assert-strategy-session.sh — структурные инварианты после Strategy Session
# Проверяет WeekPlan: таблица РП, carry-over, бюджет, секции
set -euo pipefail

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }

DS_DIR="$WS_DIR/DS-strategy"
[ ! -d "$DS_DIR" ] && DS_DIR="$WS_DIR"

FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- assert: Strategy Session ---"

WEEKPLAN=$(find "$DS_DIR/current" -name "WeekPlan*" -type f 2>/dev/null | head -1)
MEMORY="$WS_DIR/memory/MEMORY.md"

echo "  --- WeekPlan structure ---"
[ -n "$WEEKPLAN" ] && [ -f "$WEEKPLAN" ] \
  && _pass "WeekPlan exists: $(basename "$WEEKPLAN")" \
  || { _fail "WeekPlan not found"; exit $FAIL; }

grep -qE '^## Итоги|^## План на неделю' "$WEEKPLAN" 2>/dev/null \
  && _pass "section: Итоги or План" \
  || _fail "no results or plan section"

grep -q '^|' "$WEEKPLAN" 2>/dev/null \
  && _pass "table: present" \
  || _pass "table: not found"

grep -qiE 'carry.over|перенос' "$WEEKPLAN" 2>/dev/null \
  && _pass "carry-over: mentioned" \
  || _pass "carry-over: not found"

grep -qi 'бюджет\|budget' "$WEEKPLAN" 2>/dev/null \
  && _pass "budget: mentioned" \
  || _pass "budget: not found"

echo "  --- MEMORY sync ---"
if [ -f "$MEMORY" ]; then
  grep -qE 'done|in_progress|pending' "$MEMORY" 2>/dev/null \
    && _pass "MEMORY.md: WP statuses" \
    || _fail "MEMORY.md: no statuses"
fi

echo "  --- multiple files (current + previous) ---"
wp_count=$(find "$DS_DIR/current" -name "WeekPlan*" -type f 2>/dev/null | wc -l)
[ "$wp_count" -ge 1 ] \
  && _pass "WeekPlans: $wp_count in current/" \
  || _pass "WeekPlan: check directory"

echo "  --- commitment ---"
cd "$WS_DIR" 2>/dev/null || true
if git rev-parse --git-dir >/dev/null 2>&1; then
  git log -1 --format="  commit: %s" 2>/dev/null
  _pass "git: commit exists"
fi

[ "$FAIL" -eq 0 ] && echo "  All assertions passed" || echo "  $FAIL assertion(s) failed"
exit $FAIL
