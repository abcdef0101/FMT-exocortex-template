#!/usr/bin/env bash
# packages-firstboot.sh — Слой 2: npm-пакеты + клонирование репо для пользователя iwe
# Может запускаться как:
#   - через virt-customize --firstboot (от root, нужен su - iwe)
#   - через SSH (от iwe, su не нужен — детектируется автоматически)
set -euo pipefail

REQUIRED_BRANCH="${IWE_BRANCH:-0.25.1}"
REPO_URL="${IWE_REPO_URL:-https://github.com/abcdef0101/FMT-exocortex-template.git}"

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

# === Клонирование репо ===
echo "  → Cloning FMT-exocortex-template (branch $REQUIRED_BRANCH)..."
if [ -d ~/IWE/FMT-exocortex-template/.git ]; then
  echo "  ✓ Repo already exists (skip clone)"
elif [ -z "$RUN_AS_IWE" ]; then
  if git clone --branch "$REQUIRED_BRANCH" "$REPO_URL" ~/IWE/FMT-exocortex-template 2>&1 | tail -3; then
    echo "  ✓ Repo cloned"
  else
    echo "  ✗ Repo clone failed"
  fi
else
  if $RUN_AS_IWE "git clone --branch $REQUIRED_BRANCH $REPO_URL ~/IWE/FMT-exocortex-template 2>&1 | tail -3"; then
    echo "  ✓ Repo cloned"
  else
    echo "  ✗ Repo clone failed"
  fi
fi

# === Проверка ===
echo ""
echo "=== Verification ==="
command -v claude 2>/dev/null && echo "  ✓ claude" || echo "  ✗ claude not in PATH"
command -v codex 2>/dev/null && echo "  ✓ codex" || echo "  ✗ codex not in PATH"
[ -x ~/.opencode/bin/opencode ] && echo "  ✓ opencode" || echo "  ✗ opencode not found"
echo "git:  $(git --version 2>/dev/null || echo 'missing')"
echo "node: $(node --version 2>/dev/null || echo 'missing')"
echo "npm:  $(npm --version 2>/dev/null || echo 'missing')"
[ -d ~/IWE/FMT-exocortex-template ] && echo "  ✓ Repo present" || echo "  ✗ Repo missing"

echo ""
echo "✓ Firstboot complete"
