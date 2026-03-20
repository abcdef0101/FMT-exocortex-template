#!/usr/bin/env bash
# Library-Class: source-pure

if [[ -n "${_LIB_ENV_LOADED:-}" ]]; then
  return 0
fi
readonly _LIB_ENV_LOADED=1

function iwe_find_repo_root() {
  local start_dir="${1}"
  local current_dir="${start_dir}"

  while [[ "${current_dir}" != "/" ]]; do
    if [[ -f "${current_dir}/CLAUDE.md" ]] && [[ -d "${current_dir}/memory" ]]; then
      printf '%s\n' "${current_dir}"
      return 0
    fi
    current_dir="$(dirname "${current_dir}")"
  done

  return 1
}

function iwe_workspace_dir_from_repo_root() {
  local repo_root="${1}"
  dirname "${repo_root}"
}

function iwe_env_file_from_repo_root() {
  local repo_root="${1}"
  local workspace_dir
  workspace_dir="$(iwe_workspace_dir_from_repo_root "${repo_root}")"
  printf '%s/.%s/env\n' "${HOME}" "$(basename "${workspace_dir}")"
}

function iwe_project_slug_from_workspace() {
  local workspace_dir="${1}"
  printf '%s\n' "${workspace_dir//\//-}"
}

function iwe_validate_env_file() {
  local filepath="${1}"

  if grep -qE '^[[:blank:]]*(eval|source|\.)[[:blank:]]' "${filepath}" 2>/dev/null; then
    printf 'ERROR: env file contains dangerous patterns: %s\n' "${filepath}" >&2
    return 1
  fi
}

function iwe_load_env_file() {
  local filepath="${1}"

  [[ -f "${filepath}" ]] || {
    printf 'IWE env not found: %s\n' "${filepath}" >&2
    return 1
  }

  iwe_validate_env_file "${filepath}" || return 1

  set -a
  # shellcheck source=/dev/null
  source "${filepath}"
  set +a
}

function iwe_require_env_vars() {
  local var_name

  for var_name in "$@"; do
    if [[ -z "${!var_name:-}" ]]; then
      printf 'ERROR: required env var is not set: %s\n' "${var_name}" >&2
      return 1
    fi
  done
}
