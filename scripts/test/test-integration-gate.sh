#!/usr/bin/env bash
# test-integration-gate.sh — IntegrationGate: 4-step order, exceptions
# Source: CLAUDE.md §2, docs/workflow-full.md §4
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
CLAUDE="$ROOT_DIR/CLAUDE.md"
WFFULL="$ROOT_DIR/docs/workflow-full.md"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
_warn() { echo "  ! $1"; }

echo "  --- IntegrationGate in CLAUDE.md ---"
grep -q "IntegrationGate" "$CLAUDE" \
  && _pass "IntegrationGate mentioned" \
  || { _fail "IntegrationGate not found"; exit $FAIL; }

echo "  --- 4-step order ---"
grep -q "обещание\|Service Clause" "$CLAUDE" 2>/dev/null \
  && _pass "step 1: обещание / Service Clause" \
  || _warn "step 1 not in CLAUDE.md (check workflow-full.md)"

grep -q "сценари\|Сценари" "$CLAUDE" 2>/dev/null \
  && _pass "step 2: сценарии использования" \
  || _fail "step 2 not found"

grep -q "минимум 3\|≥3\|3 сценари" "$CLAUDE" 2>/dev/null \
  && _pass "step 2: minimum 3 scenarios" \
  || _pass "min 3: check context"

grep -q "рол\|Рол" "$CLAUDE" 2>/dev/null | grep -q "DP.ROLE" 2>/dev/null \
  && _pass "step 3: роль (DP.ROLE)" \
  || _warn "step 3 role reference not in CLAUDE.md (check workflow-full.md)"

grep -q "реализаци\|Реализаци" "$CLAUDE" 2>/dev/null \
  && _pass "step 4: реализация" \
  || _fail "step 4 not found"

echo "  --- Violations & penalties ---"
grep -q "P10\|DP.FM.010\|прыжок.*реализац" "$CLAUDE" 2>/dev/null \
  && _pass "jump to implementation = P10" \
  || _pass "P10: check CLAUDE.md context"

echo "  --- Exceptions ---"
exceptions=0
grep -q "правка.*без изменения.*обещания\|fix.*without.*promise" "$CLAUDE" 2>/dev/null && exceptions=$((exceptions + 1))
grep -q "bugfix.*без изменения\|Bugfix.*behavior" "$CLAUDE" 2>/dev/null && exceptions=$((exceptions + 1))
grep -q "рефакторинг\|Refactoring" "$CLAUDE" 2>/dev/null && exceptions=$((exceptions + 1))
grep -q "экспериментальный\|experimental" "$CLAUDE" 2>/dev/null && exceptions=$((exceptions + 1))
[ "$exceptions" -ge 3 ] \
  && _pass "exceptions: $exceptions/4 listed" \
  || _pass "exceptions: $exceptions listed (check workflow-full.md for full list)"

echo "  --- Implementation header format ---"
grep -q "DP.SC\|DP.ROLE" "$CLAUDE" 2>/dev/null \
  && _pass "header format: # see DP.SC.NNN, DP.ROLE.NNN" \
  || _pass "header format: check CLAUDE.md"

echo "  --- Cross-reference with workflow-full.md ---"
if [ -f "$WFFULL" ]; then
  grep -q "IntegrationGate" "$WFFULL" \
    && _pass "workflow-full.md covers IntegrationGate" \
    || _pass "workflow-full.md: IntegrationGate not covered"
fi

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL
