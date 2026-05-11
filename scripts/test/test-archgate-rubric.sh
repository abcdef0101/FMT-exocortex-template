#!/usr/bin/env bash
# test-archgate-rubric.sh — ArchGate v3: 7 ЭМОГССБ, veto rules, modernity checks
# Source: .claude/skills/archgate/SKILL.md (authoritative), CLAUDE.md §5
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
ARCHGATE="$ROOT_DIR/.claude/skills/archgate/SKILL.md"
CLAUDE="$ROOT_DIR/CLAUDE.md"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
_warn() { echo "  ! $1"; }

echo "  --- archgate SKILL.md ---"
[ -f "$ARCHGATE" ] && _pass "archgate/SKILL.md exists" || { _fail "missing"; exit $FAIL; }

echo "  --- 7 characteristics (ЭМОГССБ v3) ---"
chars=0
grep -q "Эволюционируемость" "$ARCHGATE" && chars=$((chars + 1))
grep -q "Масштабируемость" "$ARCHGATE" && chars=$((chars + 1))
grep -q "Обучаемость" "$ARCHGATE" && chars=$((chars + 1))
grep -q "Генеративность" "$ARCHGATE" && chars=$((chars + 1))
grep -q "Скорость" "$ARCHGATE" && chars=$((chars + 1))
grep -q "Современность" "$ARCHGATE" && chars=$((chars + 1))
grep -q "Безопасность" "$ARCHGATE" && chars=$((chars + 1))
[ "$chars" -ge 7 ] \
  && _pass "characteristics: $chars/7 found" \
  || _fail "characteristics: only $chars/7 found"

echo "  --- v3 conjunctive screening (profile, not aggregate score) ---"
grep -q "Достаточно\|Слабо\|Блокер\|✅\|⚠️\|❌" "$ARCHGATE" \
  && _pass "scale: ✅/⚠️/❌ (profile, no numeric)" \
  || _fail "scale not found"

grep -q "veto\|conjunctive\|Правило [1-3]" "$ARCHGATE" 2>/dev/null \
  && _pass "veto rules present" \
  || _fail "veto rules missing"

echo "  --- modernity checks ---"
grep -q "SOTA.002\|Context Engineering" "$ARCHGATE" 2>/dev/null \
  && _pass "modernity: Context Engineering (SOTA.002)" \
  || _fail "SOTA.002 missing"

grep -q "SOTA.001\|DDD Strategic" "$ARCHGATE" 2>/dev/null \
  && _pass "modernity: DDD Strategic (SOTA.001)" \
  || _fail "SOTA.001 missing"

grep -q "SOTA.011\|Coupling Model" "$ARCHGATE" 2>/dev/null \
  && _pass "modernity: Coupling Model (SOTA.011)" \
  || _fail "SOTA.011 missing"

echo "  --- ArchGate in CLAUDE.md §5 ---"
grep -q "АрхГейт\|ArchGate\|Архитектурное решение.*оценка" "$CLAUDE" 2>/dev/null \
  && _pass "ArchGate in CLAUDE.md" \
  || _fail "ArchGate not in CLAUDE.md"

grep -q "Без агрегатного балла\|только профиль\|non-compensatory" "$ARCHGATE" 2>/dev/null \
  && _pass "gate semantics: profile without aggregate ranking" \
  || _fail "gate semantics: profile-only distinction missing"

grep -q "ЭМОГССБ" "$ARCHGATE" \
  && _pass "acronym ЭМОГССБ present" \
  || _fail "ЭМОГССБ acronym missing"

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL
