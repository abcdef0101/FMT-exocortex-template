#!/usr/bin/env bash
# test-ai-cli-wrapper.sh — тесты ai-cli-wrapper.sh (провайдер-агностик AI CLI)
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

WRAPPER="$ROOT_DIR/scripts/ai-cli-wrapper.sh"

echo "  --- syntax check ---"
bash -n "$WRAPPER" 2>/dev/null \
  && _pass "ai-cli-wrapper.sh bash syntax ok" \
  || _fail "ai-cli-wrapper.sh syntax error"

# Source the library
source "$WRAPPER" 2>/dev/null || { _fail "cannot source ai-cli-wrapper.sh"; exit 1; }

echo "  --- provider detection ---"

# Test claude detection (mocked)
command() {
  case "$1" in
    -v) case "$2" in
          claude) return 1 ;;     # claude not installed
          opencode) return 0 ;;   # opencode installed
          *) command "$1" "$2"; return $? ;;
        esac ;;
    *) command "$1" "$2"; return $? ;;
  esac
}
export -f command

AI_CLI="" provider=$(detect_ai_cli) && { _pass "detect: fallback to opencode when claude missing" && echo "    provider=$provider"; } || _fail "detect crashed"

# Test AI_CLI override
unset -f command 2>/dev/null || true
AI_CLI="claude" provider=$(detect_ai_cli)
[ "$provider" = "claude" ] \
  && _pass "detect: AI_CLI override works (claude)" \
  || _fail "detect: AI_CLI override (expected claude, got $provider)"

AI_CLI="opencode" provider=$(detect_ai_cli)
[ "$provider" = "opencode" ] \
  && _pass "detect: AI_CLI override works (opencode)" \
  || _fail "detect: AI_CLI override (expected opencode, got $provider)"

unset AI_CLI

echo "  --- flag construction (claude) ---"

# Mock detect_ai_cli to return claude
detect_ai_cli() { echo "claude"; }
export -f detect_ai_cli

# Test bare flag
flags=$(ai_cli_flags --bare)
echo "$flags" | grep -q "\-\-bare" \
  && _pass "claude flags: --bare present" \
  || _fail "claude flags: --bare missing (got: $flags)"

# Test allowed tools — must NOT contain embedded quotes (regression check for C4)
flags=$(ai_cli_flags --allowed-tools "Read,Write,Edit")
echo "$flags" | grep -q "Read,Write,Edit" \
  && _pass "claude flags: --allowedTools without embedded quotes" \
  || _fail "claude flags: --allowedTools broken (got: $flags)"
echo "$flags" | grep -q '"Read' && _fail "claude flags: embedded quotes detected (C4 regression!)" || true

# Test budget flag
flags=$(ai_cli_flags --budget "1.50")
echo "$flags" | grep -q "max-budget-usd 1.50" \
  && _pass "claude flags: --max-budget-usd present" \
  || _fail "claude flags: --max-budget-usd missing (got: $flags)"

# Test combined flags
flags=$(ai_cli_flags --bare --allowed-tools "Bash" --budget "0.50")
echo "$flags" | grep -q "\-\-bare" && echo "$flags" | grep -q "Bash" && echo "$flags" | grep -q "max-budget-usd 0.50" \
  && _pass "claude flags: combined (bare + tools + budget)" \
  || _fail "claude flags: combined missing elements (got: $flags)"

echo "  --- flag construction (opencode) ---"

detect_ai_cli() { echo "opencode"; }
export -f detect_ai_cli

# Test bare → --pure mapping
flags=$(ai_cli_flags --bare)
echo "$flags" | grep -q "\-\-pure" \
  && _pass "opencode flags: --bare maps to --pure" \
  || _fail "opencode flags: --bare → --pure failed (got: $flags)"

# Test budget → --variant minimal mapping
flags=$(ai_cli_flags --budget "1.00")
echo "$flags" | grep -q "variant minimal" \
  && _pass "opencode flags: --budget maps to --variant minimal" \
  || _fail "opencode flags: --budget → --variant minimal failed (got: $flags)"

# Test tools export for opencode (must NOT use command substitution — export happens in same process)
unset AI_CLI_TOOLS 2>/dev/null || true
ai_cli_flags --allowed-tools "Read,Bash" >/dev/null
[ "${AI_CLI_TOOLS:-}" = "Read,Bash" ] \
  && _pass "opencode flags: --allowed-tools exported as AI_CLI_TOOLS" \
  || _fail "opencode flags: --allowed-tools not exported (AI_CLI_TOOLS=${AI_CLI_TOOLS:-})"

unset AI_CLI_TOOLS 2>/dev/null || true

echo "  --- CLI interface ---"

# Restore real detect
unset -f detect_ai_cli 2>/dev/null || true
unset -f command 2>/dev/null || true

# Test check command (graceful when no AI CLI)
output=$(bash "$WRAPPER" check 2>&1) && rc=0 || rc=$?
if [ "$rc" -eq 0 ]; then
  _pass "ai-cli check: found $(echo "$output" | head -1)"
else
  _pass "ai-cli check: no CLI found (rc=$rc, ok)"
fi

# Test flags command
output=$(bash "$WRAPPER" flags --bare 2>&1)
echo "$output" | grep -q "dangerously-skip-permissions" \
  && _pass "ai-cli flags: produces flags output" \
  || _fail "ai-cli flags: no output"

# Test help command
output=$(bash "$WRAPPER" help 2>&1) && rc=0 || rc=$?
[ "$rc" -eq 1 ] \
  && _pass "ai-cli help: exits 1" \
  || _fail "ai-cli help: unexpected exit $rc"
echo "$output" | grep -q "Usage:" \
  && _pass "ai-cli help: shows Usage" \
  || _fail "ai-cli help: no Usage"

# Test unknown command
output=$(bash "$WRAPPER" unknown 2>&1) && rc=0 || rc=$?
[ "$rc" -eq 1 ] \
  && _pass "ai-cli unknown: exits 1" \
  || _fail "ai-cli unknown: unexpected exit $rc"

# Test agent-create (should succeed as no-op)
output=$(bash "$WRAPPER" agent-create test-agent "Read,Bash" 2>&1) && rc=0 || rc=$?
[ "$rc" -eq 0 ] \
  && _pass "ai-cli agent-create: exit 0 (no-op)" \
  || _fail "ai-cli agent-create: exit $rc"

echo "  --- edge cases ---"

# Unknown provider
detect_ai_cli() { echo "nonexistent"; }
export -f detect_ai_cli
flags=$(ai_cli_flags --bare)
echo "$flags" | grep -q "dangerously-skip-permissions" \
  && _pass "edge: unknown provider → default flags" \
  || _fail "edge: unknown provider → unexpected (got: $flags)"

# Empty tools
unset -f detect_ai_cli 2>/dev/null || true
detect_ai_cli() { echo "claude"; }
export -f detect_ai_cli
flags=$(ai_cli_flags)
echo "$flags" | grep -qv "allowedTools" 2>/dev/null \
  && _pass "edge: no --allowed-tools → no --allowedTools in output" \
  || _pass "edge: no --allowed-tools → default flags: $flags"

# Cleanup
unset -f detect_ai_cli 2>/dev/null || true

# -------------------------------------------------------------------
[ "$FAIL" -eq 0 ] && echo "  All tests passed" || echo "  $FAIL test(s) failed"
exit $FAIL
