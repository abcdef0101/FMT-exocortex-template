#!/usr/bin/env bash
# test-protocol-work.sh — protocol-work.md: Capture-to-Pack, Decision Capture, Gates
# Source: persistent-memory/protocol-work.md
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
PWORK="$ROOT_DIR/persistent-memory/protocol-work.md"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- protocol-work.md ---"
[ -f "$PWORK" ] && _pass "file exists" || { _fail "missing"; exit $FAIL; }

echo "  --- Capture-to-Pack ---"
grep -q "Capture-to-Pack\|Capture to Pack" "$PWORK" \
  && _pass "Capture-to-Pack section" \
  || _fail "Capture-to-Pack not found"

_routes=0
grep -q "CLAUDE.md" "$PWORK" && _routes=$((_routes + 1))
grep -q "Pack" "$PWORK" && _routes=$((_routes + 1))
grep -q "memory/" "$PWORK" && _routes=$((_routes + 1))
[ "$_routes" -ge 3 ] \
  && _pass "routing: CLAUDE.md, Pack, memory/ destinations" \
  || _fail "routing destinations incomplete"

grep -q "Правило.*1-3\|1-3 строки" "$PWORK" 2>/dev/null \
  && _pass "rule: 1-3 lines → CLAUDE.md" \
  || _fail "rule format: 1-3 lines not mentioned"

echo "  --- Self-correction ---"
grep -q "Self-correction\|самокоррекци\|расхождение.*немедленно" "$PWORK" "$ROOT_DIR/CLAUDE.md" 2>/dev/null \
  && _pass "Self-correction rule" \
  || _fail "Self-correction not found in protocol-work or CLAUDE.md"

echo "  --- Decision Capture ---"
grep -q "Decision Capture\|decision.capture" "$PWORK" \
  && _pass "Decision Capture section" \
  || _fail "Decision Capture: not found"

grep -q "пользователь\|user decision" "$PWORK" 2>/dev/null \
  && _pass "only user decisions captured" \
  || _fail "user decisions: not specified"

echo "  --- Pre-action Gates ---"
grep -q "Pre-action Gate\|MAP.002\|Знай свои сервисы" "$PWORK" \
  && _pass "Pre-action Gates / MAP.002" \
  || _fail "Pre-action Gates not found"

grep -q "Pull-before-Commit\|pull.*rebase" "$PWORK" 2>/dev/null \
  && _pass "Pull-before-Commit rule" \
  || _fail "Pull-before-Commit: not found"

grep -q "Skill Discovery\|≥3 повторен\|3 повтор" "$PWORK" 2>/dev/null \
  && _pass "Skill Discovery rule" \
  || _fail "Skill Discovery: not found"

echo "  --- Day Work meta-rules ---"
grep -q "Слот 1 = саморазвитие\|self.dev slot" "$PWORK" 2>/dev/null \
  && _pass "self-dev slot 1 rule" \
  || _fail "self-dev slot: not found"

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL
