#!/usr/bin/env bash
# test-protocol-open.sh — protocol-open.md: WP Gate, Ritual, Session Log
# Source: persistent-memory/protocol-open.md
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
POPEN="$ROOT_DIR/persistent-memory/protocol-open.md"
CLAUDE="$ROOT_DIR/CLAUDE.md"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- protocol-open.md ---"
[ -f "$POPEN" ] && _pass "file exists" || { _fail "missing"; exit $FAIL; }

lines=$(wc -l < "$POPEN")
[ "$lines" -le 150 ] \
  && _pass "line count: $lines (limit: 150)" \
  || _fail "line count: $lines (limit: 150)"

echo "  --- WP Gate (блокирующее) ---"
grep -q "WP Gate\|БЛОКИРУЮЩЕЕ" "$POPEN" \
  && _pass "WP Gate section" \
  || _fail "WP Gate not found"

grep -q "СОВПАДАЕТ\|СТОП\|REGISTRY" "$POPEN" \
  && _pass "WP Gate branching: match/registry/stop" \
  || _fail "WP Gate branching not found"

grep -q '≤15\|≤ 15\|не более 15' "$POPEN" "$CLAUDE" 2>/dev/null \
  && _pass "exception: ≤15 min rule" \
  || _fail "exception: ≤15 min rule not found in protocol-open or CLAUDE.md"

echo "  --- Ritual ---"
grep -q "Ритуал\|ритуал" "$POPEN" \
  && _pass "Ritual section" \
  || _fail "Ritual not found"

grep -q "verification_class\|problem-framing" "$POPEN" 2>/dev/null \
  && _pass "verification_class / problem-framing" \
  || _fail "verification_class / problem-framing: not found"

echo "  --- Session mechanics ---"
grep -q "open-sessions.log\|session.log\|session log" "$POPEN" 2>/dev/null \
  && _pass "session log registration" \
  || _fail "session log: not found in protocol-open"

grep -q "5-place\|atomic write\|5 мест" "$POPEN" "$CLAUDE" 2>/dev/null \
  && _pass "5-place atomic write for new WP" \
  || _fail "5-place atomic write: not found"

grep -q "load-extensions.sh\|extensions" "$POPEN" \
  && _pass "extension point: load-extensions" \
  || _fail "extension point: not found in protocol-open"

grep -q "Issue Funnel\|WP-debt\|wp-new" "$POPEN" 2>/dev/null \
  && _pass "Issue Funnel / WP-debt" \
  || _fail "Issue Funnel / WP-debt: not found"

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL
