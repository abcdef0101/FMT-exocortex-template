#!/usr/bin/env bash
# assert-skill-invocation.sh — детерминированные инварианты /verify invocation
set -euo pipefail

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }

FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- assert: Skill Invocation ---"

PACK_FILE="$WS_DIR/Pack/08-service-clauses/DP.SC.025-capture-bus.md"
STANDARD="$WS_DIR/DS-strategy/docs/DP-standard.md"

echo "  --- input files present ---"
[ -f "$PACK_FILE" ] && _pass "Pack file exists" || _fail "Pack file missing"
[ -f "$STANDARD" ] && _pass "DP standard exists" || _fail "DP standard missing"

echo "  --- violations in seed ---"
# The seed intentionally has violations:
grep -q 'MISSING SECTION: Dependencies' "$PACK_FILE" 2>/dev/null \
  && _pass "seed violation: missing Dependencies" \
  || _pass "seed: Dependencies section present"
grep -c '^[0-9]\.' "$PACK_FILE" 2>/dev/null | while read n; do
  [ "${n:-0}" -lt 3 ] \
    && _pass "seed violation: $n acceptance criteria (<3)" \
    || _pass "seed: $n acceptance criteria"
done

echo "  --- standard rules present ---"
grep -qi 'Dependencies' "$STANDARD" 2>/dev/null \
  && _pass "standard: Dependencies required" \
  || _fail "standard: Dependencies not specified"
grep -qiE '≥3\|>= 3\|3 items' "$STANDARD" 2>/dev/null \
  && _pass "standard: AC ≥3 required" \
  || _pass "standard: AC count check"

echo "  --- workspace integrity ---"
[ -f "$WS_DIR/CLAUDE.md" ] && _pass "CLAUDE.md: present" || _fail "CLAUDE.md: missing"

cd "$WS_DIR" 2>/dev/null || true
[ -d .git ] && _pass "git: repo exists" || _pass "git: not initialized"

[ "$FAIL" -eq 0 ] && echo "  All assertions passed" || echo "  $FAIL assertion(s) failed"
exit $FAIL
