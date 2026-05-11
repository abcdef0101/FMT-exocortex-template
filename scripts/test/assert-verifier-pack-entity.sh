#!/usr/bin/env bash
# assert-verifier-pack-entity.sh — структурные инварианты Verifier pack-entity результата
set -euo pipefail

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }

FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- assert: Verifier Pack Entity ---"

echo "  --- verdict document ---"
VERDICT_FILE=$(find "$WS_DIR" \( -name "verdict*" -o -name "verification-*" \) -type f 2>/dev/null | head -1)
if [ -n "$VERDICT_FILE" ] && [ -f "$VERDICT_FILE" ]; then
  _pass "verdict document exists: $(basename "$VERDICT_FILE")"
  echo "  --- verdict severity ---"
  grep -qiE 'PASS|FAIL|CONDITIONAL' "$VERDICT_FILE" 2>/dev/null \
    && _pass "verdict has severity (PASS/FAIL/CONDITIONAL)" \
    || _fail "severity: no PASS/FAIL/CONDITIONAL in verdict"
else
  _fail "verdict: no verdict document found"
fi

echo "  --- missing dependencies section ---"
if [ -n "$VERDICT_FILE" ] && grep -qiE 'Dependencies|dependencies|missing.*section' "$VERDICT_FILE" 2>/dev/null; then
  _pass "missing Dependencies section detected"
else
  _fail "missing Dependencies: not detected in output"
fi

echo "  --- AC count < 3 ---"
if [ -n "$VERDICT_FILE" ] && grep -qiE 'acceptance.*criteria.*<3|<3.*AC|only [12].*criteria|недостаточно.*критери' "$VERDICT_FILE" 2>/dev/null; then
  _pass "insufficient AC count detected"
else
  _fail "insufficient AC: not detected in output"
fi

echo "  --- temporal metadata ---"
if [ -n "$VERDICT_FILE" ] && grep -qiE 'missing.*(valid_from|created|superseded)|temporal metadata' "$VERDICT_FILE" 2>/dev/null; then
  _pass "missing temporal metadata detected"
else
  _fail "temporal metadata: issues not detected in output"
fi

echo "  --- mismatch table ---"
if [ -n "$VERDICT_FILE" ] && grep -qiE 'mismatch|несоответств|violation|нарушен' "$VERDICT_FILE" 2>/dev/null; then
  _pass "mismatch table found"
else
  _fail "mismatch table: not found in output"
fi

echo "  --- standard reference ---"
[ -f "$WS_DIR/DS-strategy/docs/DP-standard.md" ] \
  && _pass "DP standard reference exists" \
  || _fail "DP standard reference missing"

echo "  --- commit ---"
cd "$WS_DIR" 2>/dev/null || true
if [ -d .git ]; then
  _pass "git: repo exists"
else
  _fail "git: not a repo"
fi

[ "$FAIL" -eq 0 ] && echo "  All assertions passed" || echo "  $FAIL assertion(s) failed"
exit $FAIL
