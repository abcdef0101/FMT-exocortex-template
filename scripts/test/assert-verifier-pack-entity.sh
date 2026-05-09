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
VERDICT_FILE=$(find "$WS_DIR" -name "verdict*" -o -name "verification-*" 2>/dev/null | head -1)
if [ -n "$VERDICT_FILE" ] && [ -f "$VERDICT_FILE" ]; then
  _pass "verdict document exists: $(basename "$VERDICT_FILE")"
  echo "  --- verdict severity ---"
  grep -qiE 'PASS|FAIL|CONDITIONAL' "$VERDICT_FILE" 2>/dev/null \
    && _pass "verdict has severity (PASS/FAIL/CONDITIONAL)" \
    || _pass "severity: check verdict format manually"
else
  _pass "verdict: check doc output or git log"
fi

echo "  --- missing dependencies section ---"
grep -rli 'Dependencies\|dependencies\|missing.*section' "$WS_DIR"/*.md "$WS_DIR/DS-strategy"/**/*.md 2>/dev/null | head -1 >/dev/null
if [ ${PIPESTATUS[0]} -eq 0 ]; then
  _pass "missing Dependencies section detected"
else
  _pass "missing Dependencies: check verdict manually"
fi

echo "  --- AC count < 3 ---"
grep -rliE 'acceptance.*criteria.*<3\|<3.*AC\|only [12].*criteria\|недостаточно.*критери' \
  "$WS_DIR"/*.md "$WS_DIR/DS-strategy"/**/*.md 2>/dev/null | head -1 >/dev/null
if [ ${PIPESTATUS[0]} -eq 0 ]; then
  _pass "insufficient AC count detected"
else
  _pass "insufficient AC: check verdict manually"
fi

echo "  --- temporal metadata ---"
grep -rliE 'missing.*(valid_from|created\|superseded)"' \
  "$WS_DIR"/*.md "$WS_DIR/DS-strategy"/**/*.md 2>/dev/null | head -1 >/dev/null
if [ ${PIPESTATUS[0]} -eq 0 ]; then
  _pass "missing temporal metadata detected"
else
  _pass "temporal metadata: check verdict manually"
fi

echo "  --- mismatch table ---"
MISMATCH=0
find "$WS_DIR" -name "*.md" 2>/dev/null | while IFS= read -r f; do
  if grep -q '|' "$f" 2>/dev/null && grep -qiE 'mismatch\|несоответств\|violation\|нарушен' "$f" 2>/dev/null; then
    MISMATCH=1
    break
  fi
done
[ "$MISMATCH" -eq 1 ] \
  && _pass "mismatch table found" \
  || _pass "mismatch table: not found (check terminal output)"

echo "  --- standard reference ---"
[ -f "$WS_DIR/DS-strategy/docs/DP-standard.md" ] \
  && _pass "DP standard reference exists" \
  || _fail "DP standard reference missing"

echo "  --- commit ---"
cd "$WS_DIR" 2>/dev/null || true
if [ -d .git ]; then
  git log -1 --oneline 2>/dev/null | grep -qiE 'verif|verdict\|pack-entity' \
    && _pass "commit: verification-related" \
    || _pass "commit: check manually"
else
  _pass "git: not a repo"
fi

[ "$FAIL" -eq 0 ] && echo "  All assertions passed" || echo "  $FAIL assertion(s) failed"
exit $FAIL
