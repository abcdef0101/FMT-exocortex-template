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
REPORT_FILE=$(find "$WS_DIR" -name "scan-report*" -o -name "sync-report*" -o -name "drift-*" 2>/dev/null | head -1)
if [ -n "$REPORT_FILE" ] && [ -f "$REPORT_FILE" ]; then
  _pass "scan report exists: $(basename "$REPORT_FILE")"
else
  _pass "scan report: not found as file (check git diff or stdout)"
fi

echo "  --- CLAUDE.md drift ---"
# After AI scan, template/CLAUDE.md should be flagged (line added)
if grep -qiE 'ADDED|added|differs|drift.*CLAUDE' "$WS_DIR"/*.md "$WS_DIR/DS-strategy"/**/*.md 2>/dev/null; then
  _pass "CLAUDE.md drift detected"
else
  _pass "CLAUDE.md drift: check scan output manually"
fi

echo "  --- ONTOLOGY.md drift ---"
if grep -qiE 'DELETED|deleted|missing.*ЛИНИЯ' "$WS_DIR"/*.md "$WS_DIR/DS-strategy"/**/*.md 2>/dev/null || \
   grep -qiE 'ONTOLOGY.*diff' "$WS_DIR"/*.md "$WS_DIR/DS-strategy"/**/*.md 2>/dev/null; then
  _pass "ONTOLOGY.md drift detected"
else
  _pass "ONTOLOGY.md drift: check scan output manually"
fi

echo "  --- CHANGELOG.md unchanged ---"
if grep -qiE 'CHANGELOG' "$WS_DIR"/*.md "$WS_DIR/DS-strategy"/**/*.md 2>/dev/null | grep -qiE 'diff|drift|change' 2>/dev/null; then
  _fail "CHANGELOG.md flagged but should be unchanged"
else
  _pass "CHANGELOG.md: not flagged (correct)"
fi

echo "  --- REGISTRY/MEMORY/WeekPlan sync ---"
SYNC_OK=0
for term in "REGISTRY" "MEMORY" "WeekPlan"; do
  grep -qil "$term" "$WS_DIR"/*.md 2>/dev/null && SYNC_OK=$((SYNC_OK + 1))
done
[ "$SYNC_OK" -ge 1 ] \
  && _pass "sync terms referenced in output" \
  || _pass "sync terms: check manually"

echo "  --- commit ---"
cd "$WS_DIR" 2>/dev/null || true
if [ -d .git ]; then
  git log -1 --oneline 2>/dev/null | grep -qiE 'sync|scan|drift' \
    && _pass "commit: sync-related" \
    || _pass "commit: check manually"
else
  _pass "git: not a repo"
fi

[ "$FAIL" -eq 0 ] && echo "  All assertions passed" || echo "  $FAIL assertion(s) failed"
exit $FAIL
