#!/usr/bin/env bash
# assert-session-prep.sh — структурные инварианты после Session Prep
# Проверяет что хедлесс-процесс создал черновик WeekPlan и архивировал старые
set -euo pipefail

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }

DS_DIR="$WS_DIR/DS-strategy"
[ ! -d "$DS_DIR" ] && DS_DIR="$WS_DIR"

FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- assert: Session Prep ---"

ARCHIVE="$DS_DIR/archive/week-plans"
MEMORY="$WS_DIR/memory/MEMORY.md"

echo "  --- WeekPlan draft created ---"
current=$(find "$DS_DIR/current" -name "WeekPlan*" -type f 2>/dev/null | head -1)
[ -n "$current" ] \
  && _pass "WeekPlan: $(basename "$current") in current/" \
  || _pass "WeekPlan: no new WeekPlan (may not have run)"

echo "  --- old archived ---"
if [ -d "$ARCHIVE" ]; then
  archived=$(find "$ARCHIVE" -name "WeekPlan*" -type f 2>/dev/null | wc -l)
  [ "$archived" -ge 1 ] \
    && _pass "archive: $archived old WeekPlan(s) archived" \
    || _pass "archive: empty (may not have run)"
fi

echo "  --- old DayPlans archived ---"
day_archive=$(find "$DS_DIR/archive" -name "DayPlan*" -type f 2>/dev/null | wc -l)
[ "$day_archive" -ge 1 ] \
  && _pass "archive: $day_archive old DayPlan(s)" \
  || _pass "archive: no DayPlans archived"

echo "  --- inbox cleaned ---"
fleeting="$DS_DIR/inbox/fleeting-notes.md"
if [ -f "$fleeting" ]; then
  bold=$(grep -c '^\*\*' "$fleeting" 2>/dev/null | head -1 || echo 0)
  [ "${bold:-0}" -eq 0 ] \
    && _pass "inbox: no unprocessed bold notes" \
    || _pass "inbox: $bold bold notes (may be new)"
fi

echo "  --- MEMORY intact ---"
if [ -f "$MEMORY" ]; then
  [ -s "$MEMORY" ] && _pass "MEMORY.md: non-empty" || _fail "MEMORY.md: empty"
fi

echo "  --- commit ---"
cd "$WS_DIR" 2>/dev/null || true
if git rev-parse --git-dir >/dev/null 2>&1; then
  git log -1 --format="  commit: %s" 2>/dev/null
  _pass "git: commit exists"
fi

[ "$FAIL" -eq 0 ] && echo "  All assertions passed" || echo "  $FAIL assertion(s) failed"
exit $FAIL
