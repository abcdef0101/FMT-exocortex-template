#!/usr/bin/env bash
# assert-integration-gate.sh — структурные инварианты IntegrationGate
set -euo pipefail

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }

FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
REPORT_FILE="$WS_DIR/inbox/integration-gate-report.md"

echo "  --- assert: IntegrationGate ---"

echo "  --- report exists ---"
[ -f "$REPORT_FILE" ] \
  && _pass "report exists: $(basename "$REPORT_FILE")" \
  || _fail "report missing: $REPORT_FILE"

echo "  --- 4-step order defined ---"
steps=0
grep -qiE 'обещание|Service Clause' "$REPORT_FILE" 2>/dev/null && steps=$((steps + 1))
grep -qiE 'сценари|scenario' "$REPORT_FILE" 2>/dev/null && steps=$((steps + 1))
grep -qiE 'рол|DP.ROLE|role' "$REPORT_FILE" 2>/dev/null && steps=$((steps + 1))
grep -qiE 'реализац|implementation' "$REPORT_FILE" 2>/dev/null && steps=$((steps + 1))
[ "$steps" -eq 4 ] \
  && _pass "4-step order: $steps/4 defined" \
  || _fail "4-step order: only $steps/4"

echo "  --- P10 penalty ---"
grep -qiE 'P10\|DP\.FM\.010\|прыжок.*реализац' "$REPORT_FILE" 2>/dev/null \
  && _pass "penalty: P10 mentioned" \
  || _fail "P10: missing from report"

echo "  --- exceptions listed ---"
exceptions=0
grep -qi 'правка.*без изменения' "$REPORT_FILE" 2>/dev/null && exceptions=$((exceptions + 1))
grep -qi 'bugfix' "$REPORT_FILE" 2>/dev/null && exceptions=$((exceptions + 1))
grep -qi 'рефакторинг\|refactor' "$REPORT_FILE" 2>/dev/null && exceptions=$((exceptions + 1))
grep -qi 'экспериментальн\|experimental' "$REPORT_FILE" 2>/dev/null && exceptions=$((exceptions + 1))
[ "$exceptions" -ge 3 ] \
  && _pass "exceptions: $exceptions/4 listed" \
  || _fail "exceptions: only $exceptions/4 listed"

echo "  --- header format ---"
grep -qiE 'DP\.SC\.\|DP\.ROLE\.' "$REPORT_FILE" 2>/dev/null \
  && _pass "header format: DP.SC.NNN, DP.ROLE.NNN" \
  || _fail "header format missing"

echo "  --- no implementation files created ---"
implementation_files=$(find "$WS_DIR" \( -path '*/.git/*' -o -name 'integration-gate-report.md' \) -prune -o -type f \( -name '*.sh' -o -name '*.py' -o -name '*.ts' -o -name '*.js' \) -print)
[ -z "$implementation_files" ] \
  && _pass "implementation blocked before code creation" \
  || _fail "unexpected implementation files created"

[ "$FAIL" -eq 0 ] && echo "  All assertions passed" || echo "  $FAIL assertion(s) failed"
exit $FAIL
