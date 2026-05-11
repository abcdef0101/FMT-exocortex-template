#!/usr/bin/env bash
# assert-extractor-offline-fallback.sh — структурные инварианты Extractor offline fallback
set -euo pipefail

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }

FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- assert: Extractor Offline Fallback ---"

echo "  --- workspace integrity ---"
[ -d "$WS_DIR/PACK-test-domain/pack/test-domain" ] \
  && _pass "PACK-test-domain/pack/ exists with entities" \
  || _fail "PACK-test-domain/pack/ missing"

[ -f "$WS_DIR/PACK-test-domain/pack/test-domain/02-domain-entities/TEST.ENTITY.001-test-pattern.md" ] \
  && _pass "existing entity TEST.ENTITY.001 present" \
  || _fail "existing entity TEST.ENTITY.001 missing"

[ -f "$WS_DIR/DS-strategy/inbox/captures.md" ] \
  && _pass "captures.md exists" \
  || _fail "captures.md missing"

[ -f "$WS_DIR/roles/extractor/config/routing.md" ] \
  && _pass "routing.md exists" \
  || _fail "routing.md missing"

echo "  --- extraction report ---"
REPORT_FILE=$(find "$WS_DIR/DS-strategy/inbox/extraction-reports" -name "offline-fallback-report.md" 2>/dev/null | head -1)
if [ -n "$REPORT_FILE" ] && [ -f "$REPORT_FILE" ]; then
  _pass "extraction report created"

  grep -qiE 'reject.*дубликат|Результат.*reject|reject.*TEST\.ENTITY' "$REPORT_FILE" 2>/dev/null \
    && _pass "duplicate candidate: reject found" \
    || _fail "duplicate candidate: no reject"

  grep -qiE 'TEST\.ENTITY\.001|test-pattern' "$REPORT_FILE" 2>/dev/null \
    && _pass "duplicate candidate: references existing entity" \
    || _fail "duplicate candidate: no reference to TEST.ENTITY.001"

  grep -qiE 'Результат.*accept|accept.*маршрут|accept.*PACK' "$REPORT_FILE" 2>/dev/null \
    && _pass "unique candidate: accept found" \
    || _fail "unique candidate: no accept"

  grep -qi 'PACK-test-domain' "$REPORT_FILE" 2>/dev/null \
    && _pass "local Pack referenced in report" \
    || _fail "local Pack NOT referenced in report"
else
  _fail "extraction report NOT created"
fi

echo "  --- offline fallback indicators ---"
if [ -n "$REPORT_FILE" ] && [ -f "$REPORT_FILE" ]; then
  grep -qiE 'MCP.*недоступ|offline|локальн|grep|find.*PACK' "$REPORT_FILE" 2>/dev/null \
    && _pass "offline fallback method indicated in report" \
    || _fail "no offline fallback indication in report"

  grep -qiE 'knowledge_search.*timeout|knowledge_search.*error|MCP.*connection.*error|Gateway.*timeout' "$REPORT_FILE" 2>/dev/null \
    && _fail "MCP connection errors in output (should not exist)" \
    || _pass "no MCP connection errors in output"

  # Check all output files in workspace for MCP errors
  MCP_ERRORS=$(find "$WS_DIR" -maxdepth 4 -name "*.md" -newer "$WS_DIR/DS-strategy/inbox/captures.md" \
    -exec grep -liE 'knowledge_search.*timeout|MCP.*connection.*error|Gateway.*timeout' {} \; 2>/dev/null | wc -l)
  [ "$MCP_ERRORS" -eq 0 ] \
    && _pass "no MCP errors in any output file" \
    || _fail "MCP errors found in $MCP_ERRORS output file(s)"
else
  _fail "cannot check fallback indicators (no report)"
fi

echo "  --- capture processing completeness ---"
if [ -f "$WS_DIR/DS-strategy/inbox/captures.md" ]; then
  CAPTURE_COUNT=$(grep -c '^### ' "$WS_DIR/DS-strategy/inbox/captures.md" 2>/dev/null || echo 0)
  if [ "$CAPTURE_COUNT" -ge 3 ] 2>/dev/null; then
    _pass "at least 3 capture candidates (duplicate + new + impl)"
  else
    _fail "less than 3 capture candidates in seed ($CAPTURE_COUNT)"
  fi
fi

[ "$FAIL" -eq 0 ] && echo "  All assertions passed" || echo "  $FAIL assertion(s) failed"
exit $FAIL
