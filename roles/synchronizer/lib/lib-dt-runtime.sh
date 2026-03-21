#!/usr/bin/env bash
# Library-Class: entrypoint-helper

if [[ -n "${_DT_RUNTIME_LIB_LOADED:-}" ]]; then
  return 0
fi
readonly _DT_RUNTIME_LIB_LOADED=1

function dt_log() {
  local log_file="${1}"
  shift
  local message="$*"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [dt-collect] ${message}" | tee -a "${log_file}"
}

function dt_load_optional_aist_env() {
  local env_file="$HOME/.config/aist/env"
  if [[ -f "${env_file}" ]]; then
    iwe_validate_env_file "${env_file}" || return 1
    set -a
    # shellcheck source=/dev/null
    source "${env_file}"
    set +a
  fi
}

function dt_check_write_prereqs() {
  local dry_run="${1}"
  local log_file="${2}"

  if [[ "${dry_run}" == "true" ]]; then
    return 0
  fi

  if [[ -z "${NEON_URL:-}" ]]; then
    dt_log "${log_file}" "NEON_URL not set — skipping"
    return 10
  fi

  if [[ -z "${DT_USER_ID:-}" ]]; then
    dt_log "${log_file}" "DT_USER_ID not set — skipping"
    return 11
  fi

  return 0
}
