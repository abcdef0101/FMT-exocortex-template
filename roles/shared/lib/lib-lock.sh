#!/usr/bin/env bash
# Library-Class: entrypoint-helper

if [[ -n "${_ROLES_SHARED_LIB_LOCK_LOADED:-}" ]]; then
  return 0
fi
readonly _ROLES_SHARED_LIB_LOCK_LOADED=1

: "${IWE_LOCK_FILES:=}"
: "${IWE_LOCK_DIRS:=}"

function iwe_lock_cleanup() {
  local exit_code=$?
  local file_path dir_path

  for file_path in ${IWE_LOCK_FILES:-}; do
    rm -f "${file_path}" 2>/dev/null || true
  done

  for dir_path in ${IWE_LOCK_DIRS:-}; do
    rm -rf "${dir_path}" 2>/dev/null || true
  done

  exit "${exit_code}"
}

function iwe_register_lock_cleanup_trap() {
  trap iwe_lock_cleanup EXIT INT TERM
}

function iwe_acquire_symlink_lock() {
  local lock_dir="${1}"
  local lock_name="${2}"
  local on_error_callback="${3:-}"

  local lock_file temp_dir
  lock_file="${lock_dir}/${lock_name}.lock"

  if ! temp_dir=$(mktemp -d "${lock_dir}/.lock.XXXXXX"); then
    if [[ -n "${on_error_callback}" ]]; then
      "${on_error_callback}" "ERROR: Cannot create temp dir for lock (${lock_name})"
    fi
    return 3
  fi

  if ! ln -s "${temp_dir}" "${lock_file}" 2>/dev/null; then
    rm -rf "${temp_dir}"
    if [[ -n "${on_error_callback}" ]]; then
      "${on_error_callback}" "SKIP: ${lock_name} already running (lock exists: ${lock_file})"
    fi
    return 2
  fi

  IWE_LOCK_FILES+=" ${lock_file}"
  IWE_LOCK_DIRS+=" ${temp_dir}"
  return 0
}
