#!/usr/bin/env bash
# test-protocol-open.sh — protocol-open.md: WP Gate, Ritual, Session Log
# Source: persistent-memory/protocol-open.md
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
POPEN="$ROOT_DIR/persistent-memory/protocol-open.md"
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

grep -q '≤15\|≤ 15\|не более 15' "$POPEN" 2>/dev/null \
  && _pass "exception: ≤15 min rule" \
  || _pass "exception: ≤15 min not in this file (see CLAUDE.md)"

echo "  --- Ritual ---"
grep -q "Ритуал\|ритуал" "$POPEN" \
  && _pass "Ritual section" \
  || _fail "Ritual not found"

grep -q "verification_class\|problem-framing" "$POPEN" 2>/dev/null \
  && _pass "verification_class / problem-framing" \
  || _pass "verification_class: not in this section"

echo "  --- Session mechanics ---"
grep -q "open-sessions.log\|session.log\|session log" "$POPEN" 2>/dev/null \
  && _pass "session log registration" \
  || _pass "session log: not in this file"

grep -q "5-place\|atomic write\|5 мест" "$POPEN" "$ROOT_DIR/CLAUDE.md" 2>/dev/null \
  && _pass "5-place atomic write for new WP" \
  || _pass "5-place write: check CLAUDE.md"

grep -q "load-extensions.sh\|extensions" "$POPEN" \
  && _pass "extension point: load-extensions" \
  || _pass "extension point: not in protocol-open"

grep -q "Issue Funnel\|WP-debt\|wp-new" "$POPEN" 2>/dev/null \
  && _pass "Issue Funnel / WP-debt" \
  || _pass "Issue Funnel: not in protocol-open"

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL
