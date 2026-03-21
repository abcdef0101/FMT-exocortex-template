#!/usr/bin/env bash
# Library-Class: entrypoint-helper

if [[ -n "${_SETUP_LIB_PREREQ_LOADED:-}" ]]; then
  return 0
fi
readonly _SETUP_LIB_PREREQ_LOADED=1

function exo_print_setup_banner() {
  local version="${1}"
  local core_only="${2}"

  if [[ "${core_only}" == "true" ]]; then
    echo "=========================================="
    echo "  Exocortex Setup v${version} (core)"
    echo "=========================================="
  else
    echo "=========================================="
    echo "  Exocortex Setup v${version}"
    echo "=========================================="
  fi
  echo ""
}

function exo_verify_template_dir() {
  local template_dir="${1}"

  if [[ ! -f "${template_dir}/CLAUDE.md" ]] || [[ ! -d "${template_dir}/memory" ]]; then
    echo "ERROR: This script must be run from the root of FMT-exocortex-template." >&2
    echo "  Expected: ${template_dir}/CLAUDE.md and ${template_dir}/memory/" >&2
    echo "" >&2
    echo "  Steps:" >&2
    echo "    gh repo fork TserenTserenov/FMT-exocortex-template --clone" >&2
    echo "    cd FMT-exocortex-template" >&2
    echo "    bash setup.sh" >&2
    return 1
  fi
}

function exo_check_command() {
  local command_name="${1}"
  local display_name="${2}"
  local install_hint="${3}"
  local required="${4:-true}"

  if command -v "${command_name}" >/dev/null 2>&1; then
    echo "  ✓ ${display_name}: $(command -v "${command_name}")"
    return 0
  fi

  if [[ "${required}" == "true" ]]; then
    echo "  ✗ ${display_name}: NOT FOUND"
    echo "    Install: ${install_hint}"
    return 1
  fi

  echo "  ○ ${display_name}: не установлен (опционально)"
  echo "    Install: ${install_hint}"
  return 0
}

function exo_check_prerequisites() {
  local core_only="${1}"
  local failures=0

  echo "Checking prerequisites..."

  exo_check_command "git" "Git" "xcode-select --install" || failures=1

  if [[ "${core_only}" == "true" ]]; then
    echo ""
    echo "  Режим --core: проверяются только обязательные зависимости (git)."
    echo "  GitHub CLI, Node.js, Claude Code — не требуются."
    echo ""
    return "${failures}"
  fi

  exo_check_command "gh" "GitHub CLI" "brew install gh" || failures=1
  exo_check_command "node" "Node.js" "brew install node (or https://nodejs.org)" || failures=1
  exo_check_command "npm" "npm" "Comes with Node.js" || failures=1
  exo_check_command "claude" "Claude Code" "npm install -g @anthropic-ai/claude-code" || failures=1

  if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
      echo "  ✓ GitHub CLI: authenticated"
    else
      echo "  ✗ GitHub CLI: not authenticated"
      echo "    Run: gh auth login"
      failures=1
    fi
  fi

  echo ""
  return "${failures}"
}
