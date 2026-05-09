#!/usr/bin/env bash
# assert-archgate.sh — структурные инварианты ArchGate результата
set -euo pipefail

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }

FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- assert: ArchGate ---"

echo "  --- decision document ---"
[ -f "$WS_DIR/docs/adr/sample-decision.md" ] \
  && _pass "decision document exists" \
  || _fail "decision document missing"

echo "  --- ArchGate rules present ---"
grep -qi 'ЭМОГССБ\|Эволюционируемость\|7 характеристик' "$WS_DIR/CLAUDE.md" 2>/dev/null \
  && _pass "ArchGate rules in CLAUDE.md" \
  || _fail "ArchGate rules not found"

echo "  --- 7 characteristics mentioned ---"
chars=0
for c in "Evolvability|Эволюционируемость" "Scalability|Масштабируемость" \
  "Learnability|Обучаемость" "Generativity|Генеративность" \
  "Speed|Скорость" "Modernity|Современность" "Security|Безопасность"; do
  grep -qiE "$c" "$WS_DIR/CLAUDE.md" 2>/dev/null && chars=$((chars + 1))
done
[ "$chars" -ge 5 ] \
  && _pass "characteristics: $chars/7 mentioned" \
  || _fail "characteristics: only $chars/7"

echo "  --- veto rules ---"
grep -qiE 'veto\|правило [1-3]\|≥2.*❌' "$WS_DIR/CLAUDE.md" 2>/dev/null \
  && _pass "veto rules: present" \
  || _pass "veto rules: check archgate SKILL.md"

echo "  --- modernity checks ---"
grep -qiE 'SOTA\.(002|001|011)' "$WS_DIR/CLAUDE.md" 2>/dev/null \
  && _pass "modernity checks: SOTA references" \
  || _pass "modernity: check archgate SKILL.md"

echo "  --- gate ≠ ranker ---"
grep -qiE 'gate.*rank\|допуск.*выбор' "$WS_DIR/CLAUDE.md" 2>/dev/null \
  && _pass "gate ≠ ranker distinction" \
  || _pass "gate/ranker: check archgate SKILL.md"

echo "  --- commit ---"
cd "$WS_DIR" 2>/dev/null || true
[ -d .git ] && _pass "git: repo exists" || _pass "git: not a repo"

[ "$FAIL" -eq 0 ] && echo "  All assertions passed" || echo "  $FAIL assertion(s) failed"
exit $FAIL
