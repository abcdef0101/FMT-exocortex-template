#!/usr/bin/env bash
# Exocortex Setup Script
# Configures a forked FMT-exocortex-template: placeholders, memory, launchd, DS-strategy
# Targets: Linux, macOS
#
# Usage:
#   bash setup.sh          # Полная установка (git + GitHub CLI + Claude Code + автоматизация)
#   bash setup.sh --core   # Минимальная установка (только git, без сети)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
TEMPLATE_DIR="$SCRIPT_DIR"

# shellcheck source=lib/lib-platform.sh
source "${SCRIPT_DIR}/lib/lib-platform.sh"

# shellcheck source=setup/lib/lib-prereq.sh
source "${SCRIPT_DIR}/setup/lib/lib-prereq.sh"

# shellcheck source=setup/lib/lib-config.sh
source "${SCRIPT_DIR}/setup/lib/lib-config.sh"

# shellcheck source=setup/lib/lib-placeholders.sh
source "${SCRIPT_DIR}/setup/lib/lib-placeholders.sh"

# shellcheck source=setup/lib/lib-install.sh
source "${SCRIPT_DIR}/setup/lib/lib-install.sh"

# shellcheck source=setup/lib/lib-verify.sh
source "${SCRIPT_DIR}/setup/lib/lib-verify.sh"

VERSION="0.4.1"
DRY_RUN=false
CORE_ONLY=false

# === Parse arguments ===
for arg in "$@"; do
  case "$arg" in
  --core) CORE_ONLY=true ;;
  --dry-run) DRY_RUN=true ;;
  --version)
    echo "exocortex-setup v$VERSION"
    exit 0
    ;;
  --help | -h)
    echo "Usage: setup.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --core      Минимальная установка: только git, без сети (офлайн)"
    echo "  --dry-run   Показать что будет сделано, без изменений"
    echo "  --version   Версия скрипта"
    echo "  --help      Эта справка"
    echo ""
    echo "Режимы:"
    echo "  full (по умолчанию)  git + GitHub CLI + Claude Code + автоматизация Стратега"
    echo "  --core               git + любой AI CLI. Без GitHub, без launchd"
    exit 0
    ;;
  esac
done

exo_print_setup_banner "$VERSION" "$CORE_ONLY"

# Verify we're inside the template
if ! exo_verify_template_dir "$TEMPLATE_DIR"; then
  exit 1
fi

echo "Template: $TEMPLATE_DIR"
echo ""

# === Prerequisites check ===
if ! exo_check_prerequisites "$CORE_ONLY"; then
  echo "ERROR: Prerequisites check failed. Install missing tools and try again." >&2
  exit 1
fi

# === Collect configuration ===
exo_collect_setup_config "$TEMPLATE_DIR" "$CORE_ONLY"
exo_print_setup_config "$CORE_ONLY"

# === Data Policy acceptance (skip in dry-run or non-interactive/CI mode) ===
if [[ "${DRY_RUN}" != "true" ]] && [[ -z "${CI:-}" ]] && [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
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
  if [[ ! "${REPLY}" =~ ^[Yy]$ ]]; then
    echo "Setup cancelled. Please review docs/DATA-POLICY.md first."
    exit 0
  fi
  echo ""

  read -p "Continue with setup? (y/n) " -n 1 -r
  echo ""
  [[ ! "${REPLY}" =~ ^[Yy]$ ]] && exit 1
fi

# === Ensure workspace exists ===
if [[ "${DRY_RUN}" == "true" ]]; then
  echo "[DRY RUN] Would create workspace: $WORKSPACE_DIR"
else
  mkdir -p "$WORKSPACE_DIR"
fi

# === Write IWE config to env file ===
echo ""
echo "[0/6] Writing IWE configuration..."
exo_write_iwe_env "$DRY_RUN"

echo ""
exo_configure_placeholders "$DRY_RUN" "$TEMPLATE_DIR"
TEMPLATE_DIR="$(exo_maybe_rename_repo "$DRY_RUN" "$CORE_ONLY" "$TEMPLATE_DIR")"

exo_install_claude_md "$DRY_RUN" "$TEMPLATE_DIR" "$WORKSPACE_DIR"
CLAUDE_MEMORY_DIR="$(exo_install_memory "$DRY_RUN" "$TEMPLATE_DIR" "$WORKSPACE_DIR")"
exo_install_claude_settings "$DRY_RUN" "$CORE_ONLY" "$TEMPLATE_DIR" "$WORKSPACE_DIR"
exo_install_roles "$DRY_RUN" "$CORE_ONLY" "$TEMPLATE_DIR"
MY_STRATEGY_DIR="$(exo_setup_strategy_repo "$DRY_RUN" "$CORE_ONLY" "$TEMPLATE_DIR" "$WORKSPACE_DIR")"
exo_print_setup_result "$DRY_RUN" "$CORE_ONLY" "$TEMPLATE_DIR" "$WORKSPACE_DIR" "$CLAUDE_MEMORY_DIR" "$MY_STRATEGY_DIR"
