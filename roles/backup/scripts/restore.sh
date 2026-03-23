#!/usr/bin/env bash
# Requires: bash>=3.2
# Targets: Linux
# Requires: openssl, gh, tar, git
#
# restore.sh — IWE User Data Restore
#
# Downloads an encrypted backup from GitHub Releases, decrypts it,
# restores user files with path remapping, and clones DS-*/Pack-* repos.
#
# Usage:
#   ./restore.sh [--tag TAG] [--workspace-dir DIR] [--repo REPO]
#
# Config (env vars or interactive prompt):
#   BACKUP_GITHUB_REPO    GitHub repo with backups (required)
#   BACKUP_PASSWORD       Decryption password (optional; prompted if not set)
#
# Exit codes:
#   0  — success
#   1  — general error
#   2  — usage error
#   3  — dependency not found
#   10 — config error

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "${0}")"

readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1
readonly EXIT_USAGE=2
readonly EXIT_DEPENDENCY=3
readonly EXIT_CONFIG=10

TMP_DIR=""
TAG=""
NEW_WORKSPACE_DIR=""
BACKUP_GITHUB_REPO="${BACKUP_GITHUB_REPO:-}"
BACKUP_PASSWORD=""

# ── Logging ───────────────────────────────────────────────────────────────────

function log_info()  { echo "INFO  [${SCRIPT_NAME}] ${*}" >&2; }
function log_warn()  { echo "WARN  [${SCRIPT_NAME}] ${*}" >&2; }
function log_error() { echo "ERROR [${SCRIPT_NAME}] ${*}" >&2; }

function die() {
  local message="${1}"
  local exit_code="${2:-${EXIT_ERROR}}"
  log_error "${message}"
  exit "${exit_code}"
}

# ── Cleanup ───────────────────────────────────────────────────────────────────

function cleanup() {
  local exit_code=$?
  if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
    rm -rf "${TMP_DIR}" 2>/dev/null || true
  fi
  exit "${exit_code}"
}

trap cleanup EXIT
trap 'log_warn "Interrupted"; exit 130' INT
trap 'log_warn "Terminated"; exit 143' TERM

# ── Helpers ───────────────────────────────────────────────────────────────────

function require_cmd() {
  local cmd="${1}"
  local hint="${2:-}"
  if ! command -v "${cmd}" > /dev/null 2>&1; then
    local msg="Required command not found: ${cmd}"
    [[ -n "${hint}" ]] && msg+=" (${hint})"
    die "${msg}" "${EXIT_DEPENDENCY}"
  fi
}

function usage() {
  cat >&2 <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Restore IWE user data from GitHub Releases backup.
DS-*/Pack-* repos: cloned from saved repo list.

Options:
  -h, --help              Show this help
  --tag TAG               Backup tag to restore (default: interactive selection)
  --workspace-dir DIR     New workspace directory (default: prompted, orig used as default)
  --repo REPO             GitHub repo with backups, e.g. user/iwe-backup

Config (env vars):
  BACKUP_GITHUB_REPO    GitHub repo for releases (required)
  BACKUP_PASSWORD       Decryption password (optional; prompted if not set)

Exit codes:
  0   Success
  1   General error
  2   Usage error
  3   Dependency not found
  10  Config error
EOF
}

# ── Argument parsing ──────────────────────────────────────────────────────────

function parse_args() {
  while [[ $# -gt 0 ]]; do
    case "${1}" in
      -h|--help)
        usage
        exit "${EXIT_SUCCESS}"
        ;;
      --tag)
        [[ $# -gt 1 ]] || die "Option ${1} requires an argument" "${EXIT_USAGE}"
        TAG="${2}"
        shift 2
        ;;
      --workspace-dir)
        [[ $# -gt 1 ]] || die "Option ${1} requires an argument" "${EXIT_USAGE}"
        NEW_WORKSPACE_DIR="${2}"
        shift 2
        ;;
      --repo)
        [[ $# -gt 1 ]] || die "Option ${1} requires an argument" "${EXIT_USAGE}"
        BACKUP_GITHUB_REPO="${2}"
        shift 2
        ;;
      -*)
        die "Unknown option: ${1}" "${EXIT_USAGE}"
        ;;
      *)
        die "Unexpected argument: ${1}" "${EXIT_USAGE}"
        ;;
    esac
  done
}

# ── Dependencies ──────────────────────────────────────────────────────────────

function check_dependencies() {
  require_cmd openssl "Install openssl via package manager"
  require_cmd tar     "Install tar via package manager"
  require_cmd git     "Install git: https://git-scm.com/"
  require_cmd gh      "Install GitHub CLI: https://cli.github.com/"
}

# ── Config ────────────────────────────────────────────────────────────────────

function load_config() {
  if [[ -z "${BACKUP_GITHUB_REPO:-}" ]]; then
    read -r -p "GitHub repo with backups (e.g. user/iwe-backup): " BACKUP_GITHUB_REPO
  fi
  [[ -n "${BACKUP_GITHUB_REPO:-}" ]] || \
    die "BACKUP_GITHUB_REPO is required" "${EXIT_CONFIG}"
}

# ── Password ──────────────────────────────────────────────────────────────────

function get_password() {
  if [[ -n "${BACKUP_PASSWORD:-}" ]]; then
    log_warn "Using BACKUP_PASSWORD from environment (ensure no process listing exposure)"
    return 0
  fi

  local password
  read -r -s -p "Backup password: " password
  echo >&2
  [[ -n "${password}" ]] || die "Password cannot be empty"

  BACKUP_PASSWORD="${password}"
  password=""
}

# ── Select backup tag ─────────────────────────────────────────────────────────

function select_backup() {
  local github_repo="${1}"

  if [[ -n "${TAG}" ]]; then
    log_info "Using specified tag: ${TAG}"
    return 0
  fi

  log_info "Fetching available backups from ${github_repo}..."

  local releases
  releases="$(gh release list --repo "${github_repo}" --limit 20 2>/dev/null)" \
    || die "Cannot list releases from ${github_repo}. Is gh authenticated? Run: gh auth login"

  [[ -n "${releases}" ]] || die "No backups found in ${github_repo}"

  echo "" >&2
  echo "Available backups:" >&2
  echo "${releases}" | head -20 >&2
  echo "" >&2

  local latest_tag
  latest_tag="$(echo "${releases}" | head -1 | awk '{print $1}')"

  read -r -p "Enter backup tag [${latest_tag}]: " TAG
  [[ -n "${TAG}" ]] || TAG="${latest_tag}"

  log_info "Selected: ${TAG}"
}

# ── Download and decrypt ──────────────────────────────────────────────────────

function download_and_decrypt() {
  local github_repo="${1}"
  local tag="${2}"
  local download_dir="${3}"

  log_info "Downloading backup ${tag} from ${github_repo}..."

  gh release download "${tag}" \
    --repo "${github_repo}" \
    --dir "${download_dir}" \
    --pattern "*.tar.gz.enc" \
    || die "Failed to download release ${tag} from ${github_repo}"

  local archive_file
  archive_file="$(find "${download_dir}" -name "*.tar.gz.enc" -type f | head -1)"
  [[ -n "${archive_file}" ]] || \
    die "No .tar.gz.enc file found in release ${tag}"

  log_info "Decrypting $(basename "${archive_file}")..."

  local decrypted="${download_dir}/backup.tar.gz"

  # [policy/00-scope.md §00.2.7] Password via stdin only
  printf '%s' "${BACKUP_PASSWORD}" \
    | openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 \
        -in "${archive_file}" \
        -out "${decrypted}" \
        -pass stdin \
    || die "Decryption failed — wrong password or corrupted archive"

  rm -f "${archive_file}"

  local extract_dir="${download_dir}/extracted"
  mkdir -p "${extract_dir}"

  log_info "Extracting archive..."
  tar -xzf "${decrypted}" -C "${extract_dir}"
  rm -f "${decrypted}"

  echo "${extract_dir}"
}

# ── Read backup metadata ──────────────────────────────────────────────────────

# read_meta: parse meta.env without sourcing (avoids polluting current env)
# Sets BACKUP_WORKSPACE_DIR, BACKUP_WORKSPACE_NAME, BACKUP_CLAUDE_SLUG, BACKUP_DATE
function read_meta() {
  local extract_dir="${1}"
  local meta_file="${extract_dir}/meta.env"

  [[ -f "${meta_file}" ]] || \
    die "meta.env not found in backup — archive may be corrupt or from old version"

  # Parse key=value lines (no eval, no source)
  local line key value
  while IFS= read -r line; do
    # Skip comments and empty lines
    [[ "${line}" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line}" ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    case "${key}" in
      BACKUP_WORKSPACE_DIR)  BACKUP_WORKSPACE_DIR="${value}" ;;
      BACKUP_WORKSPACE_NAME) BACKUP_WORKSPACE_NAME="${value}" ;;
      BACKUP_CLAUDE_SLUG)    BACKUP_CLAUDE_SLUG="${value}" ;;
      BACKUP_DATE)           BACKUP_DATE="${value}" ;;
    esac
  done < "${meta_file}"

  log_info "Backup date:       ${BACKUP_DATE:-unknown}"
  log_info "Original workspace: ${BACKUP_WORKSPACE_DIR:-unknown}"
}

# ── Resolve new workspace path ────────────────────────────────────────────────

function resolve_workspace() {
  local orig_workspace="${1}"

  if [[ -n "${NEW_WORKSPACE_DIR}" ]]; then
    log_info "Target workspace: ${NEW_WORKSPACE_DIR}"
    return 0
  fi

  echo "" >&2
  echo "Original workspace: ${orig_workspace}" >&2
  read -r -p "Restore to workspace directory [${orig_workspace}]: " NEW_WORKSPACE_DIR
  [[ -n "${NEW_WORKSPACE_DIR}" ]] || NEW_WORKSPACE_DIR="${orig_workspace}"

  log_info "Target workspace: ${NEW_WORKSPACE_DIR}"
}

# ── Restore files ─────────────────────────────────────────────────────────────

function restore_files() {
  local extract_dir="${1}"
  local new_workspace="${2}"
  local orig_workspace="${3}"
  local orig_slug="${4}"

  local new_workspace_name
  new_workspace_name="$(basename "${new_workspace}")"
  local new_slug="${new_workspace//\//-}"

  log_info "Restoring files..."

  # 1. Claude projects directory → new slug path
  local src_claude="${extract_dir}/claude-projects"
  if [[ -d "${src_claude}" ]]; then
    local dst_claude="${HOME}/.claude/projects/${new_slug}"
    mkdir -p "${dst_claude}"
    cp -r "${src_claude}/." "${dst_claude}/"
    log_info "  ✓ .claude/projects/${new_slug}/"
  fi

  # 2. CLAUDE.md
  local src_claude_md="${extract_dir}/workspace/CLAUDE.md"
  if [[ -f "${src_claude_md}" ]]; then
    mkdir -p "${new_workspace}"
    cp "${src_claude_md}" "${new_workspace}/CLAUDE.md"
    log_info "  ✓ ${new_workspace}/CLAUDE.md"
  fi

  # 3. settings.local.json
  local src_settings="${extract_dir}/workspace/.claude/settings.local.json"
  if [[ -f "${src_settings}" ]]; then
    mkdir -p "${new_workspace}/.claude"
    cp "${src_settings}" "${new_workspace}/.claude/settings.local.json"
    log_info "  ✓ ${new_workspace}/.claude/settings.local.json"
  fi

  # 4. Env file — remap WORKSPACE_DIR if workspace path changed
  local src_env="${extract_dir}/workspace-env/env"
  if [[ -f "${src_env}" ]]; then
    local dst_env_dir="${HOME}/.${new_workspace_name}"
    mkdir -p "${dst_env_dir}"
    local dst_env="${dst_env_dir}/env"

    if [[ "${new_workspace}" != "${orig_workspace}" ]]; then
      # [GNU] sed -i with empty backup suffix
      sed "s|WORKSPACE_DIR=${orig_workspace}|WORKSPACE_DIR=${new_workspace}|g" \
        "${src_env}" > "${dst_env}"
      log_info "  ✓ ${dst_env} (WORKSPACE_DIR remapped: ${orig_workspace} → ${new_workspace})"
    else
      cp "${src_env}" "${dst_env}"
      log_info "  ✓ ${dst_env}"
    fi
  fi

  # 5. Logs
  local src_logs="${extract_dir}/logs"
  if [[ -d "${src_logs}" ]]; then
    local dst_logs="${HOME}/.local/state/logs"
    mkdir -p "${dst_logs}"
    cp -r "${src_logs}/." "${dst_logs}/"
    log_info "  ✓ ~/.local/state/logs/"
  fi

  # 6. Exocortex state
  local src_exo="${extract_dir}/exocortex"
  if [[ -d "${src_exo}" ]]; then
    local dst_exo="${HOME}/.local/state/exocortex"
    mkdir -p "${dst_exo}"
    cp -r "${src_exo}/." "${dst_exo}/"
    log_info "  ✓ ~/.local/state/exocortex/"
  fi
}

# ── Clone DS-*/Pack-* repos ───────────────────────────────────────────────────

function clone_repos() {
  local extract_dir="${1}"
  local workspace_dir="${2}"

  local repo_list="${extract_dir}/repo-list.txt"
  if [[ ! -f "${repo_list}" ]] || [[ ! -s "${repo_list}" ]]; then
    log_info "No DS-*/Pack-* repos in backup (repo-list.txt empty or missing)"
    return 0
  fi

  mkdir -p "${workspace_dir}"
  log_info "Cloning DS-*/Pack-* repos..."

  local repo_name remote_url
  while IFS=' ' read -r repo_name remote_url; do
    [[ -n "${repo_name}" && -n "${remote_url}" ]] || continue

    local dest="${workspace_dir}/${repo_name}"

    if [[ -d "${dest}/.git" ]]; then
      log_info "  ${repo_name}: exists, pulling from origin..."
      git -C "${dest}" pull --rebase \
        || log_warn "  ${repo_name}: pull failed — resolve manually"
    else
      log_info "  Cloning ${repo_name}..."
      git clone "${remote_url}" "${dest}" \
        || log_warn "  ${repo_name}: clone failed (${remote_url}) — clone manually"
    fi
  done < "${repo_list}"
}

# ── Main ──────────────────────────────────────────────────────────────────────

function main() {
  parse_args "$@"
  check_dependencies
  load_config
  get_password

  TMP_DIR="$(mktemp -d)"
  local download_dir="${TMP_DIR}/download"
  mkdir -p "${download_dir}"

  # Step 1: Select backup tag
  select_backup "${BACKUP_GITHUB_REPO}"

  # Step 2: Download, decrypt, extract
  local extract_dir
  extract_dir="$(download_and_decrypt "${BACKUP_GITHUB_REPO}" "${TAG}" "${download_dir}")"

  # Step 3: Read metadata from backup
  # Sets BACKUP_WORKSPACE_DIR, BACKUP_WORKSPACE_NAME, BACKUP_CLAUDE_SLUG, BACKUP_DATE
  BACKUP_WORKSPACE_DIR=""
  BACKUP_CLAUDE_SLUG=""
  BACKUP_DATE=""
  BACKUP_WORKSPACE_NAME=""
  read_meta "${extract_dir}"

  [[ -n "${BACKUP_WORKSPACE_DIR:-}" ]] || \
    die "meta.env missing BACKUP_WORKSPACE_DIR — archive may be corrupt"

  # Step 4: Resolve target workspace path
  resolve_workspace "${BACKUP_WORKSPACE_DIR}"

  # Step 5: Restore files with path remapping
  restore_files \
    "${extract_dir}" \
    "${NEW_WORKSPACE_DIR}" \
    "${BACKUP_WORKSPACE_DIR}" \
    "${BACKUP_CLAUDE_SLUG}"

  # Step 6: Clone DS-*/Pack-* repos
  clone_repos "${extract_dir}" "${NEW_WORKSPACE_DIR}"

  log_info ""
  log_info "Restore complete from backup: ${TAG}"
  log_info ""
  log_info "Next steps:"
  log_info "  1. cd ${NEW_WORKSPACE_DIR}"
  log_info "  2. Open Claude Code from the workspace root"
  log_info "  3. Verify memory/ and CLAUDE.md are in place"
  log_info "  4. If BACKUP_PASSWORD was prompted — optionally add BACKUP_GITHUB_REPO to env"

  exit "${EXIT_SUCCESS}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
