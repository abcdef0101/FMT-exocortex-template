#!/usr/bin/env bash
# Exocortex Setup Script
# Configures a forked FMT-exocortex-template: placeholders, memory, launchd, DS-strategy
#
# Exit codes:
#   1 — validation or configuration error
#   2 — missing prerequisites (git, gh, etc.)
#   3 — clone, create, or copy failure
#   4 — role installation failure (non-fatal, script continues)
#
# Usage:
#   bash setup.sh          # Полная установка (git + GitHub CLI + Claude Code + автоматизация)
#   bash setup.sh --core   # Минимальная установка (только git, без сети)
#
set -euo pipefail

VERSION="0.6.0"
DRY_RUN=false
CORE_ONLY=false
VALIDATE_ONLY=false

# === Cross-platform sed -i ===
# macOS sed requires '' after -i, GNU sed does not
if sed --version >/dev/null 2>&1; then
  # GNU sed (Linux)
  sed_inplace() { sed -i "$@"; }
else
  # BSD sed (macOS)
  sed_inplace() { sed -i '' "$@"; }
fi

# === Parse arguments ===
for arg in "$@"; do
  case "$arg" in
  --core) CORE_ONLY=true ;;
  --dry-run) DRY_RUN=true ;;
  --version)
    echo "exocortex-setup v$VERSION"
    exit 0
    ;;
  --validate) VALIDATE_ONLY=true ;;
  --help | -h)
    echo "Usage: setup.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --validate  Проверить текущую установку (env, файлы, extensions, MCP)"
    echo "  --core      Офлайн-установка: только git, без сети"
    echo "  --dry-run   Показать что будет сделано, без изменений"
    echo "  --version   Версия скрипта"
    echo "  --help      Эта справка"
    exit 0
    ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

# === Validate mode ===
if $VALIDATE_ONLY; then
  echo "=========================================="
  echo "  Exocortex Validate v$VERSION"
  echo "=========================================="
  echo ""
  ERRORS=0

  # Check template source files (ADR-004: persistent-memory is template source-of-truth)
  echo "[1/4] Template source files..."
  CHECK_FILES=(
    "CLAUDE.md"
    "seed/CLAUDE.md"
    "seed/MEMORY.md"
    "seed/settings.local.json"
    "seed/.mcp.json"
    "seed/day-rhythm-config.yaml"
    "seed/.gitignore"
    "seed/params.yaml"
    "persistent-memory/protocol-open.md"
    "persistent-memory/protocol-close.md"
    "persistent-memory/protocol-work.md"
    "persistent-memory/navigation.md"
    "persistent-memory/roles.md"
  )
  for f in "${CHECK_FILES[@]}"; do
    if [ -f "$ROOT_DIR/$f" ]; then
      echo "  ✓ $f"
    else
      echo "  ✗ $f отсутствует"
      ERRORS=$((ERRORS + 1))
    fi
  done

  # Check workspace runtime (ADR-004: canonical workspace topology)
  echo "[2/4] Workspace runtime..."
  WS_LINK="$ROOT_DIR/workspaces/CURRENT_WORKSPACE"
  if [ -L "$WS_LINK" ]; then
    WS_DIR="$(cd "$WS_LINK" 2>/dev/null && pwd)"
    if [ -n "$WS_DIR" ] && [ -d "$WS_DIR" ]; then
      echo "  ✓ workspaces/CURRENT_WORKSPACE → $(readlink "$WS_LINK")"
      for wf in memory/MEMORY.md memory/day-rhythm-config.yaml; do
        if [ -f "$WS_DIR/$wf" ]; then
          echo "  ✓ $wf"
        else
          echo "  ✗ $wf отсутствует"
          ERRORS=$((ERRORS + 1))
        fi
      done
      if [ -L "$WS_DIR/memory/persistent-memory" ]; then
        echo "  ✓ memory/persistent-memory symlink ($(readlink "$WS_DIR/memory/persistent-memory"))"
      else
        echo "  ✗ memory/persistent-memory symlink отсутствует"
        ERRORS=$((ERRORS + 1))
      fi
    else
      echo "  ✗ workspaces/CURRENT_WORKSPACE — dangling symlink"
      ERRORS=$((ERRORS + 1))
    fi
  else
    echo "  ⚠ workspaces/CURRENT_WORKSPACE symlink не найден (настройте через iwe-workspace)"
  fi

  # Check root-level symlinks
  echo "[3/4] Root symlinks..."
  if [ -L ".claude/settings.local.json" ]; then
    if [ "$(readlink ".claude/settings.local.json")" = "../workspaces/CURRENT_WORKSPACE/.claude/settings.local.json" ]; then
      echo "  ✓ .claude/settings.local.json → ../workspaces/CURRENT_WORKSPACE/.claude/settings.local.json"
    else
      echo "  ⚠ .claude/settings.local.json → $(readlink ".claude/settings.local.json") (expected ../workspaces/CURRENT_WORKSPACE/.claude/settings.local.json)"
    fi
  else
    echo "  ⚠ .claude/settings.local.json symlink not found"
  fi
  if [ -L ".mcp.json" ]; then
    if [ "$(readlink ".mcp.json")" = "workspaces/CURRENT_WORKSPACE/.mcp.json" ]; then
      echo "  ✓ .mcp.json → workspaces/CURRENT_WORKSPACE/.mcp.json"
    else
      echo "  ⚠ .mcp.json → $(readlink ".mcp.json") (expected workspaces/CURRENT_WORKSPACE/.mcp.json)"
    fi
  else
    echo "  ⚠ .mcp.json symlink not found"
  fi

  # Check MCP accessibility
  echo "[4/4] MCP-доступность..."
  echo "  MCP подключается через claude.ai/settings/connectors"
  echo "  Проверьте командой /mcp в Claude Code"

  echo ""
  if [ "$ERRORS" -eq 0 ]; then
    echo "✓ Валидация пройдена"
  else
    echo "✗ Найдено ошибок: $ERRORS"
  fi
  exit "$ERRORS"
fi

if $CORE_ONLY; then
  echo "=========================================="
  echo "  Exocortex Setup v$VERSION (core)"
  echo "=========================================="
else
  echo "=========================================="
  echo "  Exocortex Setup v$VERSION"
  echo "=========================================="
fi
echo ""

# === Detect template directory ===
missing=()
files=(
  "$ROOT_DIR/CLAUDE.md"
  "$ROOT_DIR/persistent-memory"
  "$ROOT_DIR/seed"
  "$ROOT_DIR/seed/CLAUDE.md"
  "$ROOT_DIR/seed/MEMORY.md"
  "$ROOT_DIR/seed/settings.local.json"
  "$ROOT_DIR/seed/day-rhythm-config.yaml"
  "$ROOT_DIR/seed/params.yaml"
  "$ROOT_DIR/seed/.mcp.json"
  "$ROOT_DIR/seed/.gitignore"
)
for f in "${files[@]}"; do
  if [[ ! -e "$f" ]]; then
    missing+=("$f")
  fi
done
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "  ERROR: files not found" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  echo ""
  echo "  Steps:"
  echo "    gh repo fork TserenTserenov/FMT-exocortex-template --clone"
  echo "    cd FMT-exocortex-template"
  echo "    bash setup.sh"
  exit 1
fi
if [ ! -L ".claude/settings.local.json" ]; then
  echo "  ✗ .claude/settings.local.json symlink not found — are you in the template root?" >&2
  exit 1
fi
if [[ "$(readlink ".claude/settings.local.json")" != "../workspaces/CURRENT_WORKSPACE/.claude/settings.local.json" ]]; then
  echo "  ERROR: .claude/settings.local.json != ../workspaces/CURRENT_WORKSPACE/.claude/settings.local.json" >&2
  echo ""
  echo "  Steps:"
  echo "    gh repo fork TserenTserenov/FMT-exocortex-template --clone"
  echo "    cd FMT-exocortex-template"
  echo "    bash setup.sh"
  exit 1
fi
if [ ! -L ".mcp.json" ]; then
  echo "  ✗ .mcp.json symlink not found — are you in the template root?" >&2
  exit 1
fi
if [[ "$(readlink ".mcp.json")" != "workspaces/CURRENT_WORKSPACE/.mcp.json" ]]; then
  echo "  ERROR: This script must be run from the root of FMT-exocortex-template." >&2
  echo ""
  echo "  Steps:"
  echo "    gh repo fork TserenTserenov/FMT-exocortex-template --clone"
  echo "    cd FMT-exocortex-template"
  echo "    bash setup.sh"
  exit 1
fi

echo "ROOT DIR: $ROOT_DIR"
echo ""

# === Prerequisites check ===
echo "Checking prerequisites..."
PREREQ_FAIL=0

check_command() {
  local cmd="$1"
  local name="$2"
  local install_hint="$3"
  local required="${4:-true}"
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  ✓ $name: $(command -v "$cmd")"
  else
    if [ "$required" = "true" ]; then
      echo "  ✗ $name: NOT FOUND"
      echo "    Install: $install_hint"
      PREREQ_FAIL=1
    else
      echo "  ○ $name: не установлен (опционально)"
      echo "    Install: $install_hint"
    fi
  fi
}

# Git — обязателен всегда
check_command "git" "Git" "xcode-select --install"

if $CORE_ONLY; then
  echo ""
  echo "  Режим --core: проверяются только обязательные зависимости (git)."
  echo "  GitHub CLI, Node.js, Claude Code — не требуются."
else
  check_command "gh" "GitHub CLI" "brew install gh"
  check_command "node" "Node.js" "brew install node (or https://nodejs.org)"
  check_command "npm" "npm" "Comes with Node.js"
  check_command "claude" "Claude Code" "npm install -g @anthropic-ai/claude-code"
  check_command "jq" "commandline JSON processor" "brew install jq"

  # Check gh auth
  if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
      echo "  ✓ GitHub CLI: authenticated"
    else
      echo "  ✗ GitHub CLI: not authenticated"
      echo "    Run: gh auth login"
      PREREQ_FAIL=1
    fi
  fi
fi

echo ""

if [ "$PREREQ_FAIL" -eq 1 ]; then
  echo "ERROR: Prerequisites check failed. Install missing tools and try again."
  exit 2
fi

# === Collect configuration ===
WORKSPACES_DIR="$ROOT_DIR/workspaces"
read -p "GitHub username (или Enter для пропуска): " GITHUB_USER
GITHUB_USER="${GITHUB_USER:-your-username}"

read -p "Workspace name ($WORKSPACES_DIR/) [default-project]: " WORKSPACE_NAME

WORKSPACE_NAME="${WORKSPACE_NAME:-default-project}"

# Validate workspace name for path traversal
if [[ "$WORKSPACE_NAME" =~ \.\. ]]; then
  echo "ERROR: workspace name must not contain '..'" >&2
  exit 1
fi

if [ -z "$WORKSPACE_NAME" ]; then
  echo "ERROR: Project name cannot be empty." >&2
  exit 1
fi

if ! echo "$WORKSPACE_NAME" | grep -qxE '[a-zA-Z0-9][a-zA-Z0-9._-]*'; then
  echo "ERROR: Project name '$WORKSPACE_NAME' is invalid. Use letters, digits, hyphens, dots, underscores; must not start with a hyphen or dot." >&2
  exit 1
fi

WORKSPACE_FULL_PATH="$WORKSPACES_DIR/$WORKSPACE_NAME"
if [ -d "$WORKSPACE_FULL_PATH" ]; then
  echo "ERROR: Directory $WORKSPACE_FULL_PATH already exists. Remove it or choose another name." >&2
  exit 1
fi

# === Manifest-driven installation (ADR-005 §1) ===
echo "[2/5] Installing workspace files (manifest-driven)..."

MANIFEST_LIB="$ROOT_DIR/scripts/lib/manifest-lib.sh"
MANIFEST_FILE="$ROOT_DIR/seed/manifest.yaml"

[ -f "$MANIFEST_LIB" ] || { echo "ERROR: Manifest library not found: $MANIFEST_LIB" >&2; exit 3; }
[ -f "$MANIFEST_FILE" ] || { echo "ERROR: Manifest file not found: $MANIFEST_FILE" >&2; exit 3; }

source "$MANIFEST_LIB"

# === Ensure workspace exists ===
export WORKSPACE_FULL_PATH
if $DRY_RUN; then
  apply_manifest "$MANIFEST_FILE" true
else
  apply_manifest "$MANIFEST_FILE" false

  # MCP post-bootstrap instructions
  echo ""
  echo "  MCP knowledge servers connect through Gateway (OAuth auto-flow):"
  echo "  .mcp.json → iwe-knowledge → https://mcp.aisystant.com/mcp"
  echo "  При первом запуске Claude Code откроется браузер для входа через Ory."
  echo "  Необходима подписка «Бесконечное развитие»."
  echo ""
  echo "  Пользовательские MCP-серверы: workspace/extensions/mcps/*.json."
  echo "  После добавления файла → /add-workspace-mcps зарегистрирует в scope project."
  echo ""
  echo "  После входа проверьте командой /mcp в Claude Code."
fi

if $CORE_ONLY; then
  # Core: используем defaults, не спрашиваем Claude-специфичные параметры
  CLAUDE_PATH="${AI_CLI:-claude}"
  TIMEZONE_HOUR="4"
  TIMEZONE_DESC="4:00 UTC"
else
  read -p "Claude CLI path [$(command -v claude || echo '/opt/homebrew/bin/claude')]: " CLAUDE_PATH
  CLAUDE_PATH="${CLAUDE_PATH:-$(command -v claude || echo '/opt/homebrew/bin/claude')}"

  read -p "Strategist launch hour (UTC, 0-23) [4]: " TIMEZONE_HOUR
  TIMEZONE_HOUR="${TIMEZONE_HOUR:-4}"

  read -p "Timezone description (e.g. '7:00 MSK') [${TIMEZONE_HOUR}:00 UTC]: " TIMEZONE_DESC
  TIMEZONE_DESC="${TIMEZONE_DESC:-${TIMEZONE_HOUR}:00 UTC}"
fi

# Compute Claude project slug: /Users/alice/IWE → -Users-alice-IWE
CLAUDE_PROJECT_SLUG="$(echo "$ROOT_DIR" | tr '/' '-')"

echo ""
echo "Configuration:"
echo "  GitHub user:    $GITHUB_USER"
echo "  Workspace:      $WORKSPACE_FULL_PATH"
if $CORE_ONLY; then
  echo "  Mode:           core (offline)"
else
  echo "  Claude path:    $CLAUDE_PATH"
  echo "  Schedule hour:  $TIMEZONE_HOUR (UTC)"
  echo "  Time desc:      $TIMEZONE_DESC"
fi
echo "  Root dir:       $ROOT_DIR"
echo "  Root slug:   $CLAUDE_PROJECT_SLUG"
echo ""

# === Data Policy acceptance (skip in dry-run) ===
if ! $DRY_RUN; then
  echo "Data Policy"
  echo "  IWE collects and processes data as described in docs/DATA-POLICY.md"
  echo "  Summary: profile, sessions, and learning data are stored on the platform (Neon DB)."
  echo "  Your personal/ files stay local. Claude API receives prompts + profile context."
  echo "  You can view your data (/mydata) and delete it at any time."
  echo ""
  echo "  Full policy: docs/DATA-POLICY.md"
  echo ""
  read -p "I have read and agree to the Data Policy (y/n): " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled. Please review docs/DATA-POLICY.md first."
    exit 0
  fi
  echo ""

  read -p "Continue with setup? (y/n) " -n 1 -r
  echo ""
  [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

# === Save configuration to .exocortex.env ===

ENV_FILE="$WORKSPACE_FULL_PATH/.env"

# Create .gitignore in workspace to exclude sensitive .env
if ! $DRY_RUN; then
  printf '%s\n' '.env' >"$WORKSPACE_FULL_PATH/.gitignore"
fi

  if $DRY_RUN; then
    echo "[3.2/5] Would clone PACK-digital-platform → $PACK_DIR"
  else
    echo "[3.2/5] Cloning PACK-digital-platform..."
  if git clone --depth 1 https://github.com/TserenTserenov/PACK-digital-platform.git "$PACK_DIR" 2>/dev/null; then
    echo "  ✓ PACK-digital-platform cloned: $PACK_DIR"
  else
    echo "  ⚠ Clone failed — /iwe-rules-review будет недоступен без локального Pack"
    echo "    Установи вручную: git clone https://github.com/TserenTserenov/PACK-digital-platform.git $PACK_DIR"
  fi
fi

# === 4. Install roles (autodiscovery via role.yaml) ===
if $CORE_ONLY; then
  echo "[4/5] Автоматизация... пропущена (core mode)"
else
  echo "  Роли используют launchd (macOS) / systemd user timers (Linux)."
  echo "  См. $ROOT_DIR/roles/ROLE-CONTRACT.md"
  echo "[6/7] Installing roles..."

  MANUAL_ROLES=()

  # Discover roles by role.yaml manifests (sorted by priority)
  for role_dir in "$ROOT_DIR"/roles/*/; do
    [ -d "$role_dir" ] || continue
    role_yaml="$role_dir/role.yaml"
    [ -f "$role_yaml" ] || continue
    role_name=$(basename "$role_dir")

    if grep -q 'auto:.*true' "$role_yaml" 2>/dev/null; then
      # Auto-install role
      if [ -f "$role_dir/install.sh" ]; then
        if $DRY_RUN; then
          echo "  [DRY RUN] Would install role: $role_name (auto)"
        else
          chmod +x "$role_dir/install.sh"
          runner=$(grep '^runner:' "$role_yaml" | sed 's/runner: *//' | tr -d '"' | tr -d "'" || true)
          [ -n "$runner" ] && chmod +x "$role_dir/$runner" 2>/dev/null || true
          if [ "$role_name" = "strategist" ]; then
            bash "$role_dir/install.sh" \
              --workspace-dir "$WORKSPACE_FULL_PATH" \
              --claude-path "$CLAUDE_PATH" \
              --timezone-hour "$TIMEZONE_HOUR" \
              --namespace "$WORKSPACE_NAME" ||
              { echo "  ✗ $role_name install failed (continuing)"; }
          elif [ "$role_name" = "extractor" ]; then
            bash "$role_dir/install.sh" \
              --workspace-dir "$WORKSPACE_FULL_PATH" \
              --root-dir "$ROOT_DIR" \
              --agent-ai-path "$CLAUDE_PATH" \
              --namespace "$WORKSPACE_NAME" ||
              { echo "  ✗ $role_name install failed (continuing)"; }
          elif [ "$role_name" = "synchronizer" ]; then
            bash "$role_dir/install.sh" \
              --workspace-dir "$WORKSPACE_FULL_PATH" \
              --timezone-hour "$TIMEZONE_HOUR" \
              --namespace "$WORKSPACE_NAME" ||
              { echo "  ✗ $role_name install failed (continuing)"; }
          else
            bash "$role_dir/install.sh" ||
              { echo "  ✗ $role_name install failed (continuing)"; }
          fi
          echo "  ✓ $role_name installed"
        fi
      else
        echo "  WARN: $role_name/install.sh not found, skipping."
      fi
    else
      display=$(grep 'display_name:' "$role_yaml" 2>/dev/null | sed 's/display_name: *//' | tr -d '"' || true)
      MANUAL_ROLES+=("  - ${display:-$role_name}: bash $role_dir/install.sh")
    fi
  done

  if [ ${#MANUAL_ROLES[@]} -gt 0 ]; then
    echo ""
    echo "  Additional roles (install later when ready):"
    printf '%s\n' "${MANUAL_ROLES[@]}"
    echo "  See: $ROOT_DIR/roles/ROLE-CONTRACT.md"
  fi
fi

# === Done ===
echo ""
if $DRY_RUN; then
  echo "=========================================="
  echo "  [DRY RUN] No changes made."
  echo "=========================================="
  echo ""
  echo "Run 'bash setup.sh' (without --dry-run) to apply."
else
  echo "=========================================="
  if $CORE_ONLY; then
    echo "  Setup Complete! (core)"
  else
    echo "  Setup Complete!"
  fi
  echo "=========================================="
  echo ""
  echo "Verify installation:"
  echo "  ✓ CLAUDE.md:   $WORKSPACE_FULL_PATH/CLAUDE.md"
  echo "  ✓ Memory:      $WORKSPACE_FULL_PATH/memory ($(ls "$WORKSPACE_FULL_PATH"/memory/ 2>/dev/null) file)"
  echo "  ✓ Symlink:     $WORKSPACE_FULL_PATH/memory/persistent-memory → ($(readlink "$WORKSPACE_FULL_PATH"/memory/persistent-memory))"
  echo "  ✓ DS-strategy: $MY_STRATEGY_DIR/"
  echo "  ✓ Template:    $ROOT_DIR/"
  echo ""

  echo "Next steps:"
  echo "  1. cd $WORKSPACE_FULL_PATH"
  if $CORE_ONLY; then
    echo "  2. Запустите ваш AI CLI (Claude Code, Codex, Aider, Continue.dev и др.)"
    echo "  3. Скажите: «Проведём первую стратегическую сессию»"
  else
    echo "  2. claude"
    echo "  3. Ask Claude: «Проведём первую стратегическую сессию»"
    echo ""
    echo "Strategist will run automatically:"
    echo "  - Morning ($TIMEZONE_DESC): strategy (Mon) / day-plan (Tue-Sun)"
    echo "  - Sunday night: week review"
  fi
  echo ""
  echo "Update from upstream:"
  echo "  cd $ROOT_DIR && bash update.sh"
  echo ""
fi
