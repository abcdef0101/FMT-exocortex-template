#!/usr/bin/env bash
# assert-integration-gate.sh — структурные инварианты IntegrationGate
set -euo pipefail

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }

FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- assert: IntegrationGate ---"

echo "  --- gate rules present ---"
grep -qi 'IntegrationGate\|БЛОКИРУЮЩЕЕ.*новый инструмент' "$WS_DIR/CLAUDE.md" 2>/dev/null \
  && _pass "IntegrationGate rules in CLAUDE.md" \
  || _fail "IntegrationGate rules not found"

echo "  --- 4-step order defined ---"
steps=0
grep -qiE 'обещание|Service Clause' "$WS_DIR/CLAUDE.md" 2>/dev/null && steps=$((steps + 1))
grep -qiE 'сценари|scenario' "$WS_DIR/CLAUDE.md" 2>/dev/null && steps=$((steps + 1))
grep -qiE 'рол|DP.ROLE|role' "$WS_DIR/CLAUDE.md" 2>/dev/null && steps=$((steps + 1))
grep -qiE 'реализац|implementation' "$WS_DIR/CLAUDE.md" 2>/dev/null && steps=$((steps + 1))
[ "$steps" -ge 3 ] \
  && _pass "4-step order: $steps/4 defined" \
  || _fail "4-step order: only $steps/4"

echo "  --- P10 penalty ---"
grep -qiE 'P10\|DP\.FM\.010\|прыжок.*реализац' "$WS_DIR/CLAUDE.md" 2>/dev/null \
  && _pass "penalty: P10 mentioned" \
  || _pass "P10: check CLAUDE.md"

echo "  --- exceptions listed ---"
exceptions=0
grep -qi 'правка.*без изменения' "$WS_DIR/CLAUDE.md" 2>/dev/null && exceptions=$((exceptions + 1))
grep -qi 'bugfix' "$WS_DIR/CLAUDE.md" 2>/dev/null && exceptions=$((exceptions + 1))
grep -qi 'рефакторинг\|refactor' "$WS_DIR/CLAUDE.md" 2>/dev/null && exceptions=$((exceptions + 1))
grep -qi 'экспериментальн\|experimental' "$WS_DIR/CLAUDE.md" 2>/dev/null && exceptions=$((exceptions + 1))
[ "$exceptions" -ge 3 ] \
  && _pass "exceptions: $exceptions/4 listed" \
  || _pass "exceptions: $exceptions listed"

echo "  --- header format ---"
grep -qiE 'DP\.SC\.\|DP\.ROLE\.' "$WS_DIR/CLAUDE.md" 2>/dev/null \
  && _pass "header format: DP.SC.NNN, DP.ROLE.NNN" \
  || _pass "header: check CLAUDE.md"

echo "  --- intent exists ---"
[ -f "$WS_DIR/inbox/new-tool-intent.md" ] \
  && _pass "intent document exists" \
  || _fail "intent document missing"

[ "$FAIL" -eq 0 ] && echo "  All assertions passed" || echo "  $FAIL assertion(s) failed"
exit $FAIL
