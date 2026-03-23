#!/usr/bin/env bash
# Requires: bash>=3.2
# Targets: Linux
# Requires: openssl, gh, tar, git
#
# backup.sh — IWE User Data Backup
#
# Collects user data (memory, .claude/projects, CLAUDE.md, env, logs, exocortex),
# commits and pushes DS-*/Pack-* repos, encrypts with AES-256-CBC, uploads to
# GitHub Releases.
#
# Usage:
#   ./backup.sh [--dry-run]
#
# Config (from ~/.{WORKSPACE_NAME}/env or environment variables):
#   WORKSPACE_DIR         Workspace root directory (required)
#   BACKUP_GITHUB_REPO    GitHub repo for releases, e.g. user/iwe-backup (required)
#   BACKUP_PASSWORD       Encryption password (optional; prompted interactively if not set)
#
# Security note: BACKUP_PASSWORD should NOT be stored in env file.
# Prompt-based entry is the recommended approach.
#
# Exit codes:
#   0  — success
#   1  — general error
#   2  — usage error
#   3  — dependency not found
#   10 — config error
#   11 — repo sync failed (DS-*/Pack-* push error)

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "${0}")"
readonly VERSION="1.0.0"

readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1
readonly EXIT_USAGE=2
readonly EXIT_DEPENDENCY=3
readonly EXIT_CONFIG=10
readonly EXIT_SYNC=11

DRY_RUN=false
TMP_DIR=""
BACKUP_PASSWORD="${BACKUP_PASSWORD:-}"

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
Usage: ${SCRIPT_NAME} [--dry-run]

Backup IWE user data: commits DS-*/Pack-* repos, encrypts user data,
uploads to GitHub Releases.

Options:
  -h, --help    Show this help
  --dry-run     Show what would be done without doing it

Config (env vars or ~/.{WORKSPACE_NAME}/env):
  WORKSPACE_DIR         Workspace root directory (required)
  BACKUP_GITHUB_REPO    GitHub repo for releases (required)
  BACKUP_PASSWORD       Encryption password (optional; prompted if not set)

Exit codes:
  0   Success
  1   General error
  2   Usage error
  3   Dependency not found
  10  Config error
  11  Repo sync failed (push error — backup aborted)
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
      --dry-run)
        DRY_RUN=true
        shift
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
  # WORKSPACE_DIR may already be set via environment.
  # If not, try to resolve by scanning upward for CLAUDE.md + memory.
  if [[ -z "${WORKSPACE_DIR:-}" ]]; then
    local dir="${SCRIPT_DIR}"
    while [[ "${dir}" != "/" ]]; do
      if [[ -f "${dir}/CLAUDE.md" && -d "${dir}/memory" ]]; then
        WORKSPACE_DIR="${dir}"
        break
      fi
      dir="$(dirname "${dir}")"
    done
  fi

  [[ -n "${WORKSPACE_DIR:-}" ]] || \
    die "WORKSPACE_DIR not set and cannot be inferred from script location" "${EXIT_CONFIG}"

  local workspace_name
  workspace_name="$(basename "${WORKSPACE_DIR}")"
  local env_file="${HOME}/.${workspace_name}/env"

  if [[ -f "${env_file}" ]]; then
    # Validate env file: no eval/source/.
    if grep -qE '^[[:blank:]]*(eval|source|\.)[[:blank:]]' "${env_file}" 2>/dev/null; then
      die "Env file contains dangerous patterns: ${env_file}" "${EXIT_CONFIG}"
    fi
    set -a
    # shellcheck source=/dev/null
    source "${env_file}"
    set +a
  fi

  [[ -n "${WORKSPACE_DIR:-}" ]] || \
    die "WORKSPACE_DIR not configured" "${EXIT_CONFIG}"
  [[ -n "${BACKUP_GITHUB_REPO:-}" ]] || \
    die "BACKUP_GITHUB_REPO not configured (add to ${env_file})" "${EXIT_CONFIG}"
}

# ── Password ──────────────────────────────────────────────────────────────────

function get_password() {
  # [policy/00-scope.md §00.2.7] Password handling:
  # - Not logged, not echoed, not stored in temp files
  # - Passed to openssl via stdin only
  if [[ -n "${BACKUP_PASSWORD:-}" ]]; then
    log_warn "Using BACKUP_PASSWORD from environment (ensure no process listing exposure)"
    return 0
  fi

  local password password_confirm
  read -r -s -p "Backup password: " password
  echo >&2
  read -r -s -p "Confirm password: " password_confirm
  echo >&2

  [[ "${password}" == "${password_confirm}" ]] || die "Passwords do not match"
  [[ -n "${password}" ]] || die "Password cannot be empty"

  BACKUP_PASSWORD="${password}"
  # Clear locals — bash does not have secure memory, but at least avoid reuse
  password=""
  password_confirm=""
}

# ── DS-*/Pack-* sync ──────────────────────────────────────────────────────────

# sync_repos: commits and pushes all DS-*/Pack-* repos.
# Writes "repo_name remote_url" lines to repo_list_file.
# Fails with EXIT_SYNC if any push fails.
function sync_repos() {
  local repo_list_file="${1}"
  local workspace_dir="${2}"

  log_info "Syncing DS-*/Pack-* repos (commit + push)..."

  local repo_dir repo_name remote_url
  local found=0

  while IFS= read -r -d '' repo_dir; do
    # Skip non-git directories
    [[ -d "${repo_dir}/.git" ]] || continue

    repo_name="$(basename "${repo_dir}")"
    found=$(( found + 1 ))

    # Get remote URL — required
    remote_url="$(git -C "${repo_dir}" remote get-url origin 2>/dev/null || true)"
    [[ -n "${remote_url}" ]] || \
      die "Repo ${repo_name}: no remote 'origin' configured — cannot backup" "${EXIT_SYNC}"

    if [[ "${DRY_RUN}" == "true" ]]; then
      log_info "  [DRY-RUN] Would commit+push: ${repo_name} → ${remote_url}"
      echo "${repo_name} ${remote_url}" >> "${repo_list_file}"
      continue
    fi

    # Stage tracked modified/deleted files only (no untracked)
    local has_changes=false
    if ! git -C "${repo_dir}" diff --quiet 2>/dev/null || \
       ! git -C "${repo_dir}" diff --cached --quiet 2>/dev/null; then
      has_changes=true
    fi

    if [[ "${has_changes}" == "true" ]]; then
      log_info "  ${repo_name}: committing changes..."
      git -C "${repo_dir}" add -u
      git -C "${repo_dir}" commit \
        -m "backup: auto-commit before IWE backup $(date +%Y-%m-%d)" \
        || die "Repo ${repo_name}: commit failed" "${EXIT_SYNC}"
    else
      log_info "  ${repo_name}: no uncommitted tracked changes"
    fi

    # Push (always — may be ahead even without local changes)
    log_info "  ${repo_name}: pushing to origin..."
    git -C "${repo_dir}" push origin \
      || die "Repo ${repo_name}: push failed — fix and retry backup" "${EXIT_SYNC}"

    log_info "  ✓ ${repo_name} → ${remote_url}"
    echo "${repo_name} ${remote_url}" >> "${repo_list_file}"

  done < <(find "${workspace_dir}" -maxdepth 1 -type d \
    \( -name 'DS-*' -o -name 'Pack-*' -o -name 'PACK-*' \) -print0)

  if [[ "${found}" -eq 0 ]]; then
    log_info "  No DS-*/Pack-* repos found in ${workspace_dir}"
  else
    log_info "  Synced ${found} repo(s)"
  fi
}

# ── Collect files ─────────────────────────────────────────────────────────────

function collect_files() {
  local stage_dir="${1}"
  local workspace_dir="${2}"
  local workspace_name
  workspace_name="$(basename "${workspace_dir}")"

  # Claude project slug: workspace path with / replaced by -
  local slug="${workspace_dir//\//-}"
  local claude_project_dir="${HOME}/.claude/projects/${slug}"

  log_info "Collecting user files..."

  # 1. Claude projects directory (memory/ + conversation context)
  if [[ -d "${claude_project_dir}" ]]; then
    mkdir -p "${stage_dir}/claude-projects"
    cp -r "${claude_project_dir}/." "${stage_dir}/claude-projects/"
    log_info "  + claude-projects/ ← ${claude_project_dir}"
  else
    log_warn "Claude project dir not found: ${claude_project_dir}"
  fi

  # 2. Workspace CLAUDE.md
  if [[ -f "${workspace_dir}/CLAUDE.md" ]]; then
    mkdir -p "${stage_dir}/workspace"
    cp "${workspace_dir}/CLAUDE.md" "${stage_dir}/workspace/CLAUDE.md"
    log_info "  + workspace/CLAUDE.md"
  fi

  # 3. Workspace .claude/settings.local.json (personal permissions, MCP config)
  local settings_local="${workspace_dir}/.claude/settings.local.json"
  if [[ -f "${settings_local}" ]]; then
    mkdir -p "${stage_dir}/workspace/.claude"
    cp "${settings_local}" "${stage_dir}/workspace/.claude/settings.local.json"
    log_info "  + workspace/.claude/settings.local.json"
  fi

  # 4. Env file — strip BACKUP_PASSWORD to avoid storing it in the archive
  local env_file="${HOME}/.${workspace_name}/env"
  if [[ -f "${env_file}" ]]; then
    mkdir -p "${stage_dir}/workspace-env"
    grep -v '^BACKUP_PASSWORD=' "${env_file}" \
      > "${stage_dir}/workspace-env/env" || true
    log_info "  + workspace-env/env (BACKUP_PASSWORD stripped)"
  fi

  # 5. Logs
  local logs_dir="${HOME}/.local/state/logs"
  if [[ -d "${logs_dir}" ]]; then
    mkdir -p "${stage_dir}/logs"
    cp -r "${logs_dir}/." "${stage_dir}/logs/"
    log_info "  + logs/ ← ${logs_dir}"
  fi

  # 6. Exocortex state
  local exocortex_dir="${HOME}/.local/state/exocortex"
  if [[ -d "${exocortex_dir}" ]]; then
    mkdir -p "${stage_dir}/exocortex"
    cp -r "${exocortex_dir}/." "${stage_dir}/exocortex/"
    log_info "  + exocortex/ ← ${exocortex_dir}"
  fi
}

# ── Write metadata ────────────────────────────────────────────────────────────

function write_metadata() {
  local stage_dir="${1}"
  local workspace_dir="${2}"
  local workspace_name
  workspace_name="$(basename "${workspace_dir}")"
  local slug="${workspace_dir//\//-}"

  cat > "${stage_dir}/meta.env" <<EOF
BACKUP_WORKSPACE_DIR=${workspace_dir}
BACKUP_WORKSPACE_NAME=${workspace_name}
BACKUP_CLAUDE_SLUG=${slug}
BACKUP_DATE=$(date +%Y-%m-%d)
BACKUP_TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S)
BACKUP_VERSION=${VERSION}
EOF
  log_info "  + meta.env"
}

# ── Create encrypted archive ──────────────────────────────────────────────────

function create_archive() {
  local stage_dir="${1}"
  local output_file="${2}"

  local tmp_tar="${TMP_DIR}/backup.tar.gz"

  log_info "Creating archive..."
  (
    cd "${stage_dir}" || exit 1
    tar -czf "${tmp_tar}" .
  )

  log_info "Encrypting (AES-256-CBC, PBKDF2)..."
  # [policy/00-scope.md §00.2.7] Password passed via stdin — not visible in process list
  printf '%s' "${BACKUP_PASSWORD}" \
    | openssl enc -aes-256-cbc -pbkdf2 -iter 600000 \
        -in "${tmp_tar}" \
        -out "${output_file}" \
        -pass stdin

  rm -f "${tmp_tar}"

  local size
  size="$(du -sh "${output_file}" 2>/dev/null | cut -f1)"
  log_info "Encrypted archive ready: $(basename "${output_file}") (${size})"
}

# ── Upload to GitHub Releases ─────────────────────────────────────────────────

function upload_release() {
  local archive_file="${1}"
  local github_repo="${2}"
  local tag="${3}"

  log_info "Uploading to GitHub Releases (${github_repo}, tag: ${tag})..."

  # Create release; if it already exists, proceed to upload
  gh release create "${tag}" \
    --repo "${github_repo}" \
    --title "IWE Backup ${tag}" \
    --notes "Automated IWE user data backup" \
    2>/dev/null \
    || log_warn "Release tag ${tag} already exists, proceeding with upload"

  gh release upload "${tag}" \
    --repo "${github_repo}" \
    --clobber \
    "${archive_file}" \
    || die "Upload failed — check gh authentication: gh auth status"

  log_info "Uploaded: $(basename "${archive_file}") → ${github_repo}@${tag}"
}

# ── Main ──────────────────────────────────────────────────────────────────────

function main() {
  parse_args "$@"
  check_dependencies
  load_config

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "DRY-RUN mode — no files will be modified or uploaded"
  fi

  get_password

  TMP_DIR="$(mktemp -d)"
  local stage_dir="${TMP_DIR}/stage"
  mkdir -p "${stage_dir}"

  local timestamp
  timestamp="$(date +%Y-%m-%d-%H%M%S)"
  local archive_name="iwe-backup-${timestamp}.tar.gz.enc"
  local archive_file="${TMP_DIR}/${archive_name}"
  local tag="backup-${timestamp}"
  local repo_list_file="${stage_dir}/repo-list.txt"
  touch "${repo_list_file}"

  # Step 1: Sync DS-*/Pack-* repos (commit + push)
  # Fails hard if any push fails — backup does not proceed
  sync_repos "${repo_list_file}" "${WORKSPACE_DIR}"

  # Step 2: Collect user files
  collect_files "${stage_dir}" "${WORKSPACE_DIR}"

  # Step 3: Write metadata
  write_metadata "${stage_dir}" "${WORKSPACE_DIR}"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Stage contents:"
    find "${stage_dir}" -type f | sort >&2
    log_info "[DRY-RUN] Would create: ${archive_name}"
    log_info "[DRY-RUN] Would upload to: ${BACKUP_GITHUB_REPO}@${tag}"
    exit "${EXIT_SUCCESS}"
  fi

  # Step 4: Encrypt
  create_archive "${stage_dir}" "${archive_file}"

  # Step 5: Upload
  upload_release "${archive_file}" "${BACKUP_GITHUB_REPO}" "${tag}"

  log_info "Backup complete: ${tag}"
  exit "${EXIT_SUCCESS}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
