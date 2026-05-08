#!/usr/bin/env bash
# test-telegram-notify.sh — notify.sh: bash -n, structure, env requirements
# Source: roles/synchronizer/scripts/notify.sh (§14, workflow-full.md)
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
NOTIFY="$ROOT_DIR/roles/synchronizer/scripts/notify.sh"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- notify.sh ---"
[ -f "$NOTIFY" ] && _pass "file exists" || { _fail "missing"; exit $FAIL; }

bash -n "$NOTIFY" 2>/dev/null \
  && _pass "bash -n syntax ok" \
  || _fail "syntax error"

grep -q 'send_telegram\|SendMessage\|send_message' "$NOTIFY" 2>/dev/null \
  && _pass "send_telegram function" \
  || _pass "send_telegram: check notify.sh"

grep -q 'TELEGRAM_BOT_TOKEN' "$NOTIFY" 2>/dev/null \
  && _pass "TELEGRAM_BOT_TOKEN check" \
  || _fail "TELEGRAM_BOT_TOKEN not checked"

grep -q 'TELEGRAM_CHAT_ID' "$NOTIFY" 2>/dev/null \
  && _pass "TELEGRAM_CHAT_ID check" \
  || _pass "TELEGRAM_CHAT_ID: check notify.sh"

grep -q 'templates/\|template' "$NOTIFY" 2>/dev/null \
  && _pass "agent templates referenced" \
  || _pass "templates: check notify.sh structure"

grep -q '\-\-workspace\|\-\-env\|usage\|Usage\|USAGE' "$NOTIFY" 2>/dev/null \
  && _pass "usage message or args" \
  || _pass "usage: check notify.sh"

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL
