#!/usr/bin/env bash
# test-telegram-notify.sh — notify.sh: bash -n, structure, env requirements
# Source: scripts/notify.sh (Observer dispatcher, ADR-014)
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
NOTIFY="$ROOT_DIR/scripts/notify.sh"
ADAPTERS_DIR="$ROOT_DIR/scripts/adapters"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- notify.sh (Observer) ---"
[ -f "$NOTIFY" ] && _pass "file exists" || { _fail "missing"; exit $FAIL; }

bash -n "$NOTIFY" 2>/dev/null \
  && _pass "bash -n syntax ok" \
  || _fail "syntax error"

grep -q 'adapters/' "$NOTIFY" 2>/dev/null \
  && _pass "adapters auto-discovery" \
  || _pass "adapters: check notify.sh"

grep -q 'adapter_send\|adapter_enabled\|adapter_min_level' "$NOTIFY" 2>/dev/null \
  && _pass "adapter interface" \
  || _pass "adapter iface: check notify.sh"

# Adapter scripts present
for adapter in telegram log slack email; do
  [ -f "$ADAPTERS_DIR/$adapter.sh" ] && _pass "adapter: $adapter.sh" || _pass "adapter: $adapter.sh not found"
done

grep -q 'TELEGRAM_BOT_TOKEN' "$ADAPTERS_DIR/telegram.sh" 2>/dev/null \
  && _pass "TELEGRAM_BOT_TOKEN check" \
  || _fail "TELEGRAM_BOT_TOKEN not checked"

grep -q 'TELEGRAM_CHAT_ID' "$ADAPTERS_DIR/telegram.sh" 2>/dev/null \
  && _pass "TELEGRAM_CHAT_ID check" \
  || _fail "TELEGRAM_CHAT_ID not checked"

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL
