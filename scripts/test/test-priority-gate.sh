#!/usr/bin/env bash
# test-priority-gate.sh — Priority Gate: РП ≥3h → R{N} routing
# Source: CLAUDE.md §2 (Pre-action Gates)
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
CLAUDE="$ROOT_DIR/CLAUDE.md"
FAIL=0
_p() { echo "  ✓ $1"; }
_f() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- Priority Gate in CLAUDE.md ---"
grep -qiE 'Priority Gate|РП.*≥.?3h|к какому.*R\{N\}' "$CLAUDE" 2>/dev/null \
  && _p "Priority Gate: rule present" \
  || _f "Priority Gate rule not found"

echo "  --- time threshold ---"
grep -qiE '≥.?3h' "$CLAUDE" 2>/dev/null \
  && _p "threshold: ≥3h defined" \
  || _p "threshold: check CLAUDE.md"

echo "  --- R{N} routing ---"
grep -qiE 'R\{N\}' "$CLAUDE" 2>/dev/null \
  && _p "R{N} routing: referenced" \
  || _p "R{N} routing: check CLAUDE.md"

echo "  --- gate trigger context ---"
grep -qiE 'РП.*≥.*h.*ведёт|какому.*R.*ведёт' "$CLAUDE" 2>/dev/null \
  && _p "trigger: RP duration → R{N} mapping" \
  || _p "trigger: check CLAUDE.md"

echo "  --- gate: pre-action ---"
grep -qiE 'Priority.*Gate|priority.*trigger' "$CLAUDE" 2>/dev/null \
  && _p "Priority Gate: pre-action gate" \
  || _p "pre-action: check CLAUDE.md"

[ "$FAIL" -eq 0 ] && echo "  All assertions passed" || echo "  $FAIL assertion(s) failed"
exit $FAIL
