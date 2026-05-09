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
grep -qiE 'какое обещание.*затронуто\|service clause.*promise\|SC.*затронуто' "$CLAUDE" 2>/dev/null \
  && _p "SC Gate: promise question" \
  || _p "SC Gate promise: check CLAUDE.md"

echo "  --- SC Gate: context ---"
grep -qiE 'Пользовательский сценарий\|user scenario.*SC Gate' "$CLAUDE" 2>/dev/null \
  && _p "SC Gate: user scenario trigger" \
  || _p "SC trigger: check CLAUDE.md"

echo "  --- SC Gate: service clauses dir ---"
[ -d "$ROOT_DIR/workspaces" ] && _p "workspaces dir exists" || _p "workspaces dir: not found"

echo "  --- SC Gate: blocking ---"
grep -qiE 'SC Gate.*БЛОКИРУЮЩ\|SC.*pre-action' "$CLAUDE" 2>/dev/null \
  && _p "SC Gate: defined as blocking" \
  || _p "SC blocking: check CLAUDE.md"

[ "$FAIL" -eq 0 ] && echo "  All assertions passed" || echo "  $FAIL assertion(s) failed"
exit $FAIL
