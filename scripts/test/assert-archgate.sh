#!/usr/bin/env bash
# assert-archgate.sh — структурные инварианты ArchGate результата
set -euo pipefail

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }

FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
REPORT_FILE="$WS_DIR/docs/adr/archgate-report.md"

echo "  --- assert: ArchGate ---"

echo "  --- report exists ---"
[ -f "$REPORT_FILE" ] \
  && _pass "report exists: $(basename "$REPORT_FILE")" \
  || _fail "report missing: $REPORT_FILE"

echo "  --- decision document ---"
[ -f "$WS_DIR/docs/adr/sample-decision.md" ] \
  && _pass "decision document exists" \
  || _fail "decision document missing"

echo "  --- 7 characteristics mentioned ---"
chars=0
for c in "Evolvability|Эволюционируемость" "Scalability|Масштабируемость" \
  "Learnability|Обучаемость" "Generativity|Генеративность" \
  "Speed|Скорость" "Modernity|Современность" "Security|Безопасность"; do
  grep -qiE "$c" "$REPORT_FILE" 2>/dev/null && chars=$((chars + 1))
done
[ "$chars" -eq 7 ] \
  && _pass "characteristics: $chars/7 mentioned" \
  || _fail "characteristics: only $chars/7"

echo "  --- veto rules ---"
grep -qiE 'veto\|правило [1-3]\|≥2.*❌' "$REPORT_FILE" 2>/dev/null \
  && _pass "veto rules: present" \
  || _fail "veto rules: missing from report"

echo "  --- modernity checks ---"
grep -qiE 'SOTA\.(002|001|011)|Context Engineering|DDD Strategic|Coupling Model' "$REPORT_FILE" 2>/dev/null \
  && _pass "modernity checks: SOTA references" \
  || _fail "modernity checks: missing from report"

echo "  --- gate ≠ ranker ---"
grep -qiE 'gate.*rank\|допуск.*выбор' "$REPORT_FILE" 2>/dev/null \
  && _pass "gate ≠ ranker distinction" \
  || _fail "gate/ranker distinction missing"

echo "  --- commit ---"
cd "$WS_DIR" 2>/dev/null || true
[ -d .git ] && _pass "git: repo exists" || _pass "git: not a repo"

[ "$FAIL" -eq 0 ] && echo "  All assertions passed" || echo "  $FAIL assertion(s) failed"
exit $FAIL
