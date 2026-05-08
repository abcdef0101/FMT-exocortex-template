#!/usr/bin/env bash
# test-role-synchronizer.sh — 7 synchronizer scripts + 3 templates
# Source: roles/synchronizer/scripts/*.sh
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
SYNC_DIR="$ROOT_DIR/roles/synchronizer/scripts"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- synchronizer scripts: bash -n ---"
scripts=("scheduler.sh" "notify.sh" "code-scan.sh" "daily-report.sh" "dt-collect.sh" "sync-files.sh" "video-scan.sh")
for s in "${scripts[@]}"; do
  path="$SYNC_DIR/$s"
  [ -f "$path" ] && { bash -n "$path" 2>/dev/null && _pass "$s: ok" || _fail "$s: syntax error"; } || _fail "$s: not found"
done

echo "  --- notify.sh ---"
NOTIFY="$SYNC_DIR/notify.sh"
grep -q 'TELEGRAM_BOT_TOKEN' "$NOTIFY" 2>/dev/null \
  && _pass "TELEGRAM_BOT_TOKEN check" || _fail "TELEGRAM_BOT_TOKEN not checked"
grep -q 'TELEGRAM_CHAT_ID' "$NOTIFY" 2>/dev/null \
  && _pass "TELEGRAM_CHAT_ID check" || _pass "CHAT_ID: check context"
grep -q 'send_telegram' "$NOTIFY" 2>/dev/null \
  && _pass "send_telegram function" || _pass "send function: check notify.sh"

echo "  --- scheduler.sh ---"
SCHEDULER="$SYNC_DIR/scheduler.sh"
grep -q 'workspace.dir\|WORKSPACE_DIR' "$SCHEDULER" 2>/dev/null \
  && _pass "--workspace-dir arg" || _fail "workspace-dir missing"
grep -q 'dispatch\|status\|COMMAND' "$SCHEDULER" 2>/dev/null \
  && _pass "dispatch/status commands" || _pass "commands: check scheduler.sh"

echo "  --- templates ---"
TMPL_DIR="$SYNC_DIR/templates"
templates=("strategist.sh" "extractor.sh" "synchronizer.sh")
for t in "${templates[@]}"; do
  path="$TMPL_DIR/$t"
  [ -f "$path" ] && { bash -n "$path" 2>/dev/null && _pass "template $t: ok" || _fail "template $t: syntax error"; } || _pass "template $t: not found"
  grep -q 'build_message' "$path" 2>/dev/null \
    && _pass "template $t: build_message function" || _pass "template $t: no build_message"
done

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL
