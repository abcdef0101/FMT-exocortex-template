#!/usr/bin/env bash
# Library-Class: entrypoint-helper

if [[ -n "${_ROLES_SHARED_LIB_NOTIFY_LOADED:-}" ]]; then
  return 0
fi
readonly _ROLES_SHARED_LIB_NOTIFY_LOADED=1

function iwe_notify_local() {
  local title="${1}"
  local message="${2}"

  if [[ "${OSTYPE}" == "darwin"* ]]; then
    printf 'display notification "%s" with title "%s"' "${message}" "${title}" | osascript 2>/dev/null || true
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send "${title}" "${message}" 2>/dev/null || true
  fi
}

function iwe_notify_via_script() {
  local notify_script="${1}"
  local title="${2}"
  local message="${3}"
  local level="${4:-notice}"
  local log_file="${5}"

  if [[ -f "${notify_script}" ]]; then
    "${notify_script}" "${title}" "${message}" "${level}" >> "${log_file}" 2>&1 || true
  fi
}
