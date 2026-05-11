#!/usr/bin/env bash
# test-sc-gate.sh — SC Gate: обещание service clause для пользовательских сценариев
# Source: CLAUDE.md §2 (Pre-action Gates)
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
CLAUDE="$ROOT_DIR/CLAUDE.md"
FAIL=0
_p() { echo "  ✓ $1"; }
_f() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- SC Gate in CLAUDE.md ---"
grep -qiE 'SC Gate|service.clause|08-service-clauses' "$CLAUDE" 2>/dev/null \
  && _p "SC Gate: rule present" \
  || _f "SC Gate rule not found"

echo "  --- SC Gate: promise check ---"
grep -qi 'какое обещание' "$CLAUDE" 2>/dev/null \
  && _p "SC Gate: promise question" \
  || _f "SC Gate promise: not found"

echo "  --- SC Gate: context ---"
grep -qi 'Пользовательский сценарий' "$CLAUDE" 2>/dev/null \
  && _p "SC Gate: user scenario trigger" \
  || _f "SC Gate trigger: user scenario not found"

echo "  --- SC Gate: service clauses dir ---"
[ -d "$ROOT_DIR/workspaces" ] \
  && _p "workspaces dir exists" \
  || _f "workspaces dir: not found"

echo "  --- SC Gate: blocking ---"
{ grep -q 'SC Gate' "$CLAUDE" && grep -q 'Pre-action Gates' "$CLAUDE"; } \
  && _p "SC Gate: defined under Pre-action Gates" \
  || _f "SC Gate: not linked to Pre-action Gates section"

[ "$FAIL" -eq 0 ] && echo "  All assertions passed" || echo "  $FAIL assertion(s) failed"
exit $FAIL
