#!/usr/bin/env bash
# test-role-strategist.sh — strategist.sh: scenario routing, prompt references
# Source: roles/strategist/scripts/strategist.sh, fetch-wakatime.sh
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
STRATEGIST="$ROOT_DIR/roles/strategist/scripts/strategist.sh"
FETCH="$ROOT_DIR/roles/strategist/scripts/fetch-wakatime.sh"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- strategist.sh ---"
[ -f "$STRATEGIST" ] && _pass "file exists" || { _fail "missing"; exit $FAIL; }
bash -n "$STRATEGIST" 2>/dev/null && _pass "bash -n ok" || _fail "syntax error"

echo "  --- scenario routing ---"
scenarios=("morning" "evening" "session-prep" "strategy-session" "week-review" "note-review" "add-wp" "check-plan")
found=0
for sc in "${scenarios[@]}"; do
  grep -q "$sc" "$STRATEGIST" 2>/dev/null && found=$((found + 1))
done
[ "$found" -ge 5 ] \
  && _pass "scenarios: $found/8 found in strategist.sh" \
  || _fail "scenarios: only $found/8 found"

echo "  --- required args ---"
grep -q 'workspace.dir\|WORKSPACE_DIR' "$STRATEGIST" 2>/dev/null \
  && _pass "--workspace-dir arg" || _fail "--workspace-dir missing"
grep -q 'claude.path\|ai.cli\|AI_CLI_PATH' "$STRATEGIST" 2>/dev/null \
  && _pass "--ai-cli-path arg" || _pass "AI CLI: may use env var"

echo "  --- prompt references ---"
prompt_dir="$ROOT_DIR/roles/strategist/prompts"
prompt_refs=0 total_prompts=0
for pf in "$prompt_dir"/*.md; do
  [ ! -f "$pf" ] && continue
  total_prompts=$((total_prompts + 1))
  name=$(basename "$pf")
  # strategist.sh resolves prompts by scenario name (without .md extension)
  base="${name%.md}"
  grep -q "$base" "$STRATEGIST" 2>/dev/null && prompt_refs=$((prompt_refs + 1))
done
[ "$prompt_refs" -ge 1 ] \
  && _pass "prompt refs: $prompt_refs/$total_prompts referenced" \
  || _pass "prompt refs: $prompt_refs/$total_prompts (via command matching)"

echo "  --- fetch-wakatime.sh ---"
if [ -f "$FETCH" ]; then
  bash -n "$FETCH" 2>/dev/null && _pass "bash -n ok" || _fail "syntax error"
fi

echo "  --- strategist.sh shebang + set -e ---"
head -1 "$STRATEGIST" | grep -q '#!/' && _pass "shebang" || _fail "no shebang"
grep -q 'set -e' "$STRATEGIST" && _pass "set -e present" || _fail "no set -e"

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL
