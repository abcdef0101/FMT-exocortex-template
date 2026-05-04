#!/usr/bin/env bash
# packages-firstboot.sh — Слой 2: npm-пакеты + клонирование репо для пользователя iwe
# Может запускаться как:
#   - через virt-customize --firstboot (от root, нужен su - iwe)
#   - через SSH (от iwe, su не нужен — детектируется автоматически)
set -euo pipefail

REQUIRED_BRANCH="${IWE_BRANCH:-0.25.1}"
REPO_URL="${IWE_REPO_URL:-https://github.com/abcdef0101/FMT-exocortex-template.git}"

echo "=== Packages Firstboot: Layer 2 (user iwe) ==="

# Detecting execution context
if [ "$(whoami)" = "iwe" ]; then
  RUN_AS_IWE=""
else
  RUN_AS_IWE="sudo -u iwe -i"
fi

# === npm: глобальные пакеты для iwe ===
echo "  Installing npm packages..."

if [ -z "$RUN_AS_IWE" ]; then
  npm set prefix ~/.local 2>/dev/null
  npm install -g @anthropic-ai/claude-code 2>&1 | tail -1 && echo "  ✓ claude-code" || echo "  ⚠ claude-code install failed (OK if offline)"
  npm install -g @openai/codex 2>&1 | tail -1 && echo "  ✓ codex" || echo "  ⚠ codex install failed (OK if offline)"
  npm install --prefix ~/.opencode @opencode-ai/plugin 2>&1 | tail -1 && echo "  ✓ opencode" || echo "  ⚠ opencode install failed (OK if offline)"
else
  $RUN_AS_IWE "npm set prefix ~/.local 2>/dev/null"
  $RUN_AS_IWE "npm install -g @anthropic-ai/claude-code 2>&1 | tail -1" && echo "  ✓ claude-code" || echo "  ⚠ claude-code install failed (OK if offline)"
  $RUN_AS_IWE "npm install -g @openai/codex 2>&1 | tail -1" && echo "  ✓ codex" || echo "  ⚠ codex install failed (OK if offline)"
  $RUN_AS_IWE "npm install --prefix ~/.opencode @opencode-ai/plugin 2>&1 | tail -1" && echo "  ✓ opencode" || echo "  ⚠ opencode install failed (OK if offline)"
fi

# === Клонирование репо ===
echo "  Cloning FMT-exocortex-template (branch $REQUIRED_BRANCH)..."
if [ -z "$RUN_AS_IWE" ]; then
  git clone --branch "$REQUIRED_BRANCH" "$REPO_URL" ~/IWE/FMT-exocortex-template 2>&1 | tail -1
  echo "  ✓ Repo cloned"
else
  $RUN_AS_IWE "git clone --branch $REQUIRED_BRANCH $REPO_URL ~/IWE/FMT-exocortex-template 2>&1 | tail -1"
  echo "  ✓ Repo cloned"
fi

# === Проверка ===
echo ""
echo "=== Verification ==="
echo "PATH: $PATH"
command -v claude 2>/dev/null && echo "  ✓ claude" || echo "  ✗ claude not in PATH (needs new shell)"
command -v codex 2>/dev/null && echo "  ✓ codex" || echo "  ✗ codex not in PATH"
ls ~/.opencode/bin/opencode 2>/dev/null && echo "  ✓ opencode" || echo "  ✗ opencode not found"
echo "git:  $(git --version 2>/dev/null || echo 'missing')"
echo "node: $(node --version 2>/dev/null || echo 'missing')"
echo "npm:  $(npm --version 2>/dev/null || echo 'missing')"
[ -d ~/IWE/FMT-exocortex-template ] && echo "  ✓ Repo present" || echo "  ✗ Repo missing"

echo ""
echo "✓ Firstboot complete"
