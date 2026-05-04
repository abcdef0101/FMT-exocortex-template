#!/usr/bin/env bash
# packages-firstboot.sh — Слой 2: npm-пакеты для пользователя iwe (без git clone)
# Может запускаться как:
#   - через virt-customize --firstboot (от root, нужен su - iwe)
#   - через SSH (от iwe, su не нужен — детектируется автоматически)
# Git clone выполняется отдельно в test-from-golden.sh при каждом прогоне
set -euo pipefail

echo "=== Packages Firstboot: Layer 2 (user iwe) ==="

# Detect execution context
if [ "$(whoami)" = "iwe" ]; then
  RUN_AS_IWE=""
else
  RUN_AS_IWE="sudo -u iwe -i"
fi

# Ensure required directories exist
if [ -z "$RUN_AS_IWE" ]; then
  mkdir -p ~/.local/bin ~/.opencode ~/IWE
else
  $RUN_AS_IWE "mkdir -p ~/.local/bin ~/.opencode ~/IWE"
fi

# === npm: глобальные пакеты для iwe ===
echo "  Installing npm packages..."

_npm_install() {
  local pkg_name="$1"
  local npm_cmd="$2"
  echo "  → $pkg_name..."
  if [ -z "$RUN_AS_IWE" ]; then
    if $npm_cmd 2>&1 | tail -3; then
      echo "  ✓ $pkg_name"
    else
      echo "  ⚠ $pkg_name install failed (OK if offline)"
    fi
  else
    if $RUN_AS_IWE "$npm_cmd 2>&1 | tail -3"; then
      echo "  ✓ $pkg_name"
    else
      echo "  ⚠ $pkg_name install failed (OK if offline)"
    fi
  fi
}

if [ -z "$RUN_AS_IWE" ]; then
  npm set prefix ~/.local 2>/dev/null || true
fi

_npm_install "claude-code" "npm install -g @anthropic-ai/claude-code"
_npm_install "codex"      "npm install -g @openai/codex"
_npm_install "opencode"   "npm install --prefix ~/.opencode @opencode-ai/plugin"

# === Проверка ===
echo ""
echo "=== Verification ==="
command -v claude 2>/dev/null && echo "  ✓ claude" || echo "  ✗ claude not in PATH"
command -v codex 2>/dev/null && echo "  ✓ codex" || echo "  ✗ codex not in PATH"
[ -x ~/.opencode/bin/opencode ] && echo "  ✓ opencode" || echo "  ✗ opencode not found"
echo "git:  $(git --version 2>/dev/null || echo 'missing')"
echo "node: $(node --version 2>/dev/null || echo 'missing')"
echo "npm:  $(npm --version 2>/dev/null || echo 'missing')"

echo ""
echo "✓ Firstboot complete"
