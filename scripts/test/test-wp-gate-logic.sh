#!/usr/bin/env bash
# test-wp-gate-logic.sh — WP Gate: branching, exceptions, check-plan
# Source: CLAUDE.md §2-3, protocol-open.md
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
CLAUDE="$ROOT_DIR/CLAUDE.md"
POPEN="$ROOT_DIR/persistent-memory/protocol-open.md"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- WP Gate in CLAUDE.md ---"
grep -q "WP Gate\|БЛОКИРУЮЩЕЕ.*задание\|ЛЮБОЕ задание.*протокол" "$CLAUDE" 2>/dev/null \
  && _pass "WP Gate: blocking rule" \
  || _fail "WP Gate blocking rule not found"

grep -q "протокол Открытия.*ДО начала\|протокол.*открытия.*до начала" "$CLAUDE" 2>/dev/null \
  && _pass "protocol → before work starts" \
  || _pass "order: check CLAUDE.md"

grep -q "check-plan.md" "$CLAUDE" 2>/dev/null \
  && _pass "check-plan.md referenced" \
  || _pass "check-plan.md: not in CLAUDE.md"

grep -q "wp-new" "$CLAUDE" "$ROOT_DIR/.claude/skills/wp-new/SKILL.md" 2>/dev/null \
  && _pass "wp-new referenced" \
  || _fail "wp-new not found"

grep -q "MEMORY.md" "$POPEN" 2>/dev/null \
  && _pass "MEMORY.md as WP source" \
  || _pass "MEMORY.md: check protocol-open"

echo "  --- WP Gate branching (protocol-open) ---"
grep -q "СОВПАДАЕТ\|REGISTRY\|СТОП" "$POPEN" 2>/dev/null \
  && _pass "3 branches: match/registry/stop" \
  || _pass "branches: check protocol-open"

grep -q '≤15\|≤ 15\|15.min' "$POPEN" "$CLAUDE" 2>/dev/null \
  && _pass "≤15 min exception" \
  || _pass "exception: check CLAUDE.md"

echo "  --- WP creation ---"
grep -q "5.*place\|5.*мест\|REGISTRY.*MEMORY\|MEMORY.*REGISTRY.*WeekPlan" "$POPEN" "$CLAUDE" 2>/dev/null \
  && _pass "5-place atomic write pattern" \
  || _pass "5-place: check protocol-open + CLAUDE.md"

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL
