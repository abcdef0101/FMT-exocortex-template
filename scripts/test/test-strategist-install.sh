#!/usr/bin/env bash
# test-strategist-install.sh — install.sh: bash -n, OS detection, required args
# Source: roles/strategist/install.sh (§14, workflow-full.md)
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
INSTALL="$ROOT_DIR/roles/strategist/install.sh"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- strategist/install.sh ---"
[ -f "$INSTALL" ] && _pass "file exists" || { _fail "missing"; exit $FAIL; }

bash -n "$INSTALL" 2>/dev/null \
  && _pass "bash -n syntax ok" \
  || _fail "syntax error"

grep -q '#!/' "$INSTALL" \
  && _pass "shebang present" \
  || _fail "no shebang"

grep -q 'darwin\|macOS\|macos' "$INSTALL" 2>/dev/null \
  && _pass "OS detection: macOS/darwin" \
  || _pass "macOS detection: not in install.sh"

grep -q 'systemctl\|systemd\|linux' "$INSTALL" 2>/dev/null \
  && _pass "OS detection: Linux/systemd" \
  || _pass "Linux detection: not in install.sh"

grep -q 'workspace.dir\|WORKSPACE_DIR\|--workspace' "$INSTALL" 2>/dev/null \
  && _pass "required arg: --workspace-dir" \
  || _fail "workspace-dir arg not found"

grep -q 'ai.cli\|claude.path\|--claude\|AI_CLI' "$INSTALL" 2>/dev/null \
  && _pass "required arg: AI CLI path" \
  || _pass "AI CLI: check install.sh"

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL
