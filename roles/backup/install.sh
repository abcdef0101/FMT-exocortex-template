#!/usr/bin/env bash
# Requires: bash>=3.2
# Targets: Linux
#
# install.sh — Backup role setup
#
# Checks dependencies, makes scripts executable, prints setup instructions.
# No daemons or timers — backup is manual-only.
#
# Usage:
#   ./install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "${0}")"

function log_info()  { echo "INFO  [${SCRIPT_NAME}] ${*}" >&2; }
function log_warn()  { echo "WARN  [${SCRIPT_NAME}] ${*}" >&2; }
function log_error() { echo "ERROR [${SCRIPT_NAME}] ${*}" >&2; }

function die() { log_error "${1}"; exit "${2:-1}"; }

function require_cmd() {
  local cmd="${1}" hint="${2:-}"
  if ! command -v "${cmd}" > /dev/null 2>&1; then
    local msg="Required command not found: ${cmd}"
    [[ -n "${hint}" ]] && msg+=" (${hint})"
    log_warn "${msg}"
    return 1
  fi
  return 0
}

log_info "Installing backup role..."

# Check dependencies (warn, don't fail — user may install later)
all_ok=true
require_cmd openssl "apt install openssl / brew install openssl" || all_ok=false
require_cmd tar     "part of coreutils"                          || all_ok=false
require_cmd git     "https://git-scm.com/"                       || all_ok=false
require_cmd gh      "https://cli.github.com/"                    || all_ok=false

# Make scripts executable
chmod +x "${SCRIPT_DIR}/scripts/backup.sh"
chmod +x "${SCRIPT_DIR}/scripts/restore.sh"

log_info "  ✓ backup.sh — executable"
log_info "  ✓ restore.sh — executable"

if [[ "${all_ok}" != "true" ]]; then
  log_warn "Some dependencies are missing — install them before running backup/restore"
fi

echo "" >&2
log_info "Setup checklist:"
log_info "  1. Create a PRIVATE GitHub repo for backups (e.g. your-user/iwe-backup)"
log_info "  2. Authenticate GitHub CLI:   gh auth login"
log_info "  3. Add to ~/.{WORKSPACE_NAME}/env:"
log_info "       BACKUP_GITHUB_REPO=your-user/iwe-backup"
log_info "  4. Do NOT store BACKUP_PASSWORD in the env file — enter it at prompt"
echo "" >&2
log_info "Usage:"
log_info "  Backup:  ${SCRIPT_DIR}/scripts/backup.sh"
log_info "  Restore: ${SCRIPT_DIR}/scripts/restore.sh"
log_info "  Dry run: ${SCRIPT_DIR}/scripts/backup.sh --dry-run"
