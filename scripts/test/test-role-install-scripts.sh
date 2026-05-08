#!/usr/bin/env bash
# test-role-install-scripts.sh — все install.sh: bash -n, args, OS detection
# Source: roles/{strategist,extractor,synchronizer,verifier,auditor}/install.sh
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

install_scripts=(
  "$ROOT_DIR/roles/strategist/install.sh"
  "$ROOT_DIR/roles/extractor/install.sh"
  "$ROOT_DIR/roles/synchronizer/install.sh"
  "$ROOT_DIR/roles/verifier/install.sh"
  "$ROOT_DIR/roles/auditor/install.sh"
)

echo "  --- install scripts: bash -n ---"
for script in "${install_scripts[@]}"; do
  name="${script#$ROOT_DIR/roles/}"
  if [ -f "$script" ]; then
    if bash -n "$script" 2>/dev/null; then
      _pass "$name: syntax ok"
    else
      _fail "$name: syntax error"
    fi
  else
    _fail "$name: file not found"
  fi
done

echo "  --- required args ---"
for script in "${install_scripts[@]}"; do
  name="${script#$ROOT_DIR/roles/}"
  [ ! -f "$script" ] && continue
  grep -q 'workspace.dir\|WORKSPACE_DIR\|--workspace' "$script" 2>/dev/null \
    && _pass "$name: --workspace-dir arg" \
    || _fail "$name: --workspace-dir missing"
  grep -q 'claude.path\|ai.cli\|CLAUDE_PATH\|AI_CLI\|--claude\|--ai-cli\|AGENT_AI_PATH\|AGENT_AI' "$script" 2>/dev/null \
    && _pass "$name: AI CLI path arg" \
    || _pass "$name: no AI CLI arg (may not need AI for this role)"
done

echo "  --- OS detection ---"
os_detect=0
for script in "${install_scripts[@]}"; do
  if grep -q 'darwin\|systemctl\|systemd\|launchd' "$script" 2>/dev/null; then
    os_detect=$((os_detect + 1))
  fi
done
[ "$os_detect" -ge 3 ] \
  && _pass "OS detection: $os_detect/5 scripts" \
  || _fail "OS detection: only $os_detect/5"

echo "  --- shebang ---"
for script in "${install_scripts[@]}"; do
  name="${script#$ROOT_DIR/roles/}"
  [ ! -f "$script" ] && continue
  head -1 "$script" | grep -q '#!/' \
    && _pass "$name: shebang" \
    || _fail "$name: no shebang"
done

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL
