#!/usr/bin/env bash
# assert-synchronizer-code-scan.sh — структурные инварианты Synchronizer code-scan результата
set -euo pipefail

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }

FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- assert: Synchronizer Code Scan ---"

echo "  --- scan output ---"
REPORT_FILE=$(find "$WS_DIR" \( -name "scan-report*" -o -name "sync-report*" -o -name "drift-*" \) -type f 2>/dev/null | head -1)
if [ -n "$REPORT_FILE" ] && [ -f "$REPORT_FILE" ]; then
  _pass "scan report exists: $(basename "$REPORT_FILE")"
else
  _fail "scan report: not found as file"
fi

echo "  --- CLAUDE.md drift ---"
if [ -n "$REPORT_FILE" ] && grep -qiE 'CLAUDE.*(ADDED|added|differs|drift)|drift.*CLAUDE' "$REPORT_FILE" 2>/dev/null; then
  _pass "CLAUDE.md drift detected"
else
  _fail "CLAUDE.md drift: not detected in output"
fi

echo "  --- ONTOLOGY.md drift ---"
if [ -n "$REPORT_FILE" ] && grep -qiE 'ONTOLOGY.*(DELETED|deleted|diff)|missing.*ЛИНИЯ' "$REPORT_FILE" 2>/dev/null; then
  _pass "ONTOLOGY.md drift detected"
else
  _fail "ONTOLOGY.md drift: not detected in output"
fi

echo "  --- CHANGELOG.md unchanged ---"
if [ -n "$REPORT_FILE" ] && grep -qi 'CHANGELOG' "$REPORT_FILE" 2>/dev/null; then
  if grep -qiE 'CHANGELOG.*(diff|drift|changed)' "$REPORT_FILE" 2>/dev/null; then
    _fail "CHANGELOG.md flagged but should be unchanged"
  else
    _pass "CHANGELOG.md: mentioned but not flagged (correct)"
  fi
else
  _pass "CHANGELOG.md: not mentioned (correct)"
fi

echo "  --- REGISTRY/MEMORY/WeekPlan sync ---"
SYNC_OK=0
for term in "REGISTRY" "MEMORY" "WeekPlan"; do
  [ -n "$REPORT_FILE" ] && grep -qi "$term" "$REPORT_FILE" 2>/dev/null && SYNC_OK=$((SYNC_OK + 1))
done
[ "$SYNC_OK" -ge 3 ] \
  && _pass "sync terms referenced in output" \
  || _fail "sync terms: missing in output"

echo "  --- commit ---"
cd "$WS_DIR" 2>/dev/null || true
if [ -d .git ]; then
  _pass "git: repo exists"
else
  _fail "git: not a repo"
fi

[ "$FAIL" -eq 0 ] && echo "  All assertions passed" || echo "  $FAIL assertion(s) failed"
exit $FAIL
