#!/usr/bin/env bash
# test-protocol-close.sh — protocol-close.md: Quick Close 4 steps, R23 (bash scripts/verify-close.sh)
# Source: persistent-memory/protocol-close.md
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
PCLOSE="$ROOT_DIR/persistent-memory/protocol-close.md"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- protocol-close.md ---"
[ -f "$PCLOSE" ] && _pass "file exists" || { _fail "missing"; exit $FAIL; }

lines=$(wc -l < "$PCLOSE")
[ "$lines" -le 150 ] \
  && _pass "line count: $lines (limit: 150)" \
  || _fail "line count: $lines (limit: 150)"

echo "  --- Quick Close structure ---"
grep -q "Quick Close" "$PCLOSE" \
  && _pass "Quick Close section" \
  || _fail "Quick Close not found"

grep -q "Commit.*Push\|commit.*push" "$PCLOSE" \
  && _pass "step 1: commit + push" \
  || _fail "commit+push step missing"
grep -q "WP Context\|Осталось\|What.s Left" "$PCLOSE" \
  && _pass "step 2: WP Context update" \
  || _fail "WP Context step missing"
grep -q "KE\|Knowledge Extraction\|Экстракци" "$PCLOSE" \
  && _pass "step 3: KE routing" \
  || _fail "KE step missing"
grep -q "MEMORY.md.*статус\|MEMORY.md.*status\|MEMORY.*update" "$PCLOSE" 2>/dev/null \
  && _pass "step 4: MEMORY.md status update" \
  || _fail "MEMORY.md step missing"

echo "  --- WP Context format ---"
grep -q "Осталось\|Что пробовали\|Следующий шаг" "$PCLOSE" 2>/dev/null \
  && _pass "WP Context fields: Осталось/Что пробовали/Следующий шаг" \
  || _fail "WP Context fields: none of expected fields found"

grep -q "→ memory:" "$PCLOSE" 2>/dev/null \
  && _pass "→ memory: mandatory field" \
  || _fail "→ memory: mandatory field not found"

echo "  --- Verification ---"
grep -q "R23 (bash scripts/verify-close.sh)\|Верификаци" "$PCLOSE" 2>/dev/null \
  && _pass "R23 (bash scripts/verify-close.sh) verification" \
  || _fail "verification: R23 reference not found"

grep -q "≤15 мин\|≤ 15\|15 min" "$PCLOSE" 2>/dev/null \
  && _pass "exception: ≤15 min skip verification" \
  || _fail "exception: ≤15 min skip not found"

echo "  --- Delegation ---"
grep -q "/day-close\|day.close" "$PCLOSE" 2>/dev/null \
  && _pass "Day Close delegation" \
  || _fail "Day Close delegation not found"
grep -q "/week-close\|week.close" "$PCLOSE" 2>/dev/null \
  && _pass "Week Close delegation" \
  || _fail "Week Close delegation not found"

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL
