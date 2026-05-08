#!/usr/bin/env bash
# test-role-extractor-verifier-auditor.sh — extractor, verifier, auditor scripts
# Source: roles/{extractor,verifier,auditor}/scripts/*.sh
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- extractor.sh ---"
EXTRACTOR="$ROOT_DIR/roles/extractor/scripts/extractor.sh"
[ -f "$EXTRACTOR" ] && _pass "file exists" || { _fail "missing"; exit $FAIL; }
bash -n "$EXTRACTOR" 2>/dev/null && _pass "bash -n ok" || _fail "syntax error"
grep -q 'workspace.dir\|WORKSPACE_DIR' "$EXTRACTOR" 2>/dev/null && _pass "--workspace-dir" || _pass "workspace: check arg format"
grep -q 'scenario\|PROMPT\|prompt' "$EXTRACTOR" 2>/dev/null && _pass "scenario prompt routing" || _fail "no scenario routing"

scenarios=("inbox-check" "knowledge-audit" "session-close" "on-demand" "health-test")
prompt_dir="$ROOT_DIR/roles/extractor/prompts"
for sc in "${scenarios[@]}"; do
  prompt="$prompt_dir/$sc.md"
  [ -f "$prompt" ] \
    && _pass "prompt: $sc.md exists" \
    || _fail "prompt: $sc.md missing"
done

echo "  --- verifier.sh ---"
VERIFIER="$ROOT_DIR/roles/verifier/scripts/verifier.sh"
[ -f "$VERIFIER" ] && _pass "file exists" || _fail "missing"
bash -n "$VERIFIER" 2>/dev/null && _pass "bash -n ok" || _fail "syntax error"

v_scenarios=("verify-pack-entity" "verify-content" "verify-wp-acceptance")
v_prompt_dir="$ROOT_DIR/roles/verifier/prompts"
for sc in "${v_scenarios[@]}"; do
  prompt="$v_prompt_dir/$sc.md"
  [ -f "$prompt" ] \
    && _pass "prompt: $sc.md exists" \
    || _fail "prompt: $sc.md missing"
done

echo "  --- auditor.sh ---"
AUDITOR="$ROOT_DIR/roles/auditor/scripts/auditor.sh"
[ -f "$AUDITOR" ] && _pass "file exists" || _fail "missing"
bash -n "$AUDITOR" 2>/dev/null && _pass "bash -n ok" || _fail "syntax error"

a_scenarios=("audit-plan-consistency" "audit-coverage")
a_prompt_dir="$ROOT_DIR/roles/auditor/prompts"
for sc in "${a_scenarios[@]}"; do
  prompt="$a_prompt_dir/$sc.md"
  [ -f "$prompt" ] \
    && _pass "prompt: $sc.md exists" \
    || _fail "prompt: $sc.md missing"
done

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL
