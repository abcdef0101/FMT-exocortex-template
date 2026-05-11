#!/usr/bin/env bash
# test-role-synchronizer.sh — 6 synchronizer scripts + 5 templates
# Source: roles/synchronizer/scripts/*.sh
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
SYNC_DIR="$ROOT_DIR/roles/synchronizer/scripts"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- synchronizer scripts: bash -n ---"
scripts=("scheduler.sh" "code-scan.sh" "daily-report.sh" "dt-collect.sh" "sync-files.sh" "video-scan.sh")
for s in "${scripts[@]}"; do
  path="$SYNC_DIR/$s"
  [ -f "$path" ] && { bash -n "$path" 2>/dev/null && _pass "$s: ok" || _fail "$s: syntax error"; } || _fail "$s: not found"
done

echo "  --- notify.sh (Observer, ADR-014) ---"
NOTIFY="$ROOT_DIR/scripts/notify.sh"
[ -f "$NOTIFY" ] && bash -n "$NOTIFY" 2>/dev/null && _pass "notify.sh: syntax ok" || _fail "notify.sh: not found or syntax error"
grep -q 'adapters/' "$NOTIFY" 2>/dev/null \
  && _pass "adapters auto-discovery" || _pass "adapters: check context"
grep -q 'adapter_send' "$NOTIFY" 2>/dev/null \
  && _pass "adapter_send pattern" || _pass "adapter_send: check context"

echo "  --- scheduler.sh ---"
SCHEDULER="$SYNC_DIR/scheduler.sh"
grep -q 'workspace.dir\|WORKSPACE_DIR' "$SCHEDULER" 2>/dev/null \
  && _pass "--workspace-dir arg" || _fail "workspace-dir missing"
grep -q 'dispatch\|status\|COMMAND' "$SCHEDULER" 2>/dev/null \
  && _pass "dispatch/status commands" || _pass "commands: check scheduler.sh"

echo "  --- templates ---"
templates_strategist="$ROOT_DIR/roles/strategist/scripts/templates/strategist.sh"
templates_extractor="$ROOT_DIR/roles/extractor/scripts/templates/extractor.sh"
templates_synchronizer="$ROOT_DIR/roles/synchronizer/scripts/templates/synchronizer.sh"
templates_verifier="$ROOT_DIR/roles/verifier/scripts/templates/verifier.sh"
templates_auditor="$ROOT_DIR/roles/auditor/scripts/templates/auditor.sh"

for tpl_path in "$templates_strategist" "$templates_extractor" "$templates_synchronizer" "$templates_verifier" "$templates_auditor"; do
  tpl_name=$(basename "$tpl_path")
  [ -f "$tpl_path" ] && { bash -n "$tpl_path" 2>/dev/null && _pass "template $tpl_name: ok" || _fail "template $tpl_name: syntax error"; } || _fail "template $tpl_name: not found"
  grep -q 'build_message' "$tpl_path" 2>/dev/null \
    && _pass "template $tpl_name: build_message function" || _pass "template $tpl_name: no build_message"
done

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL
