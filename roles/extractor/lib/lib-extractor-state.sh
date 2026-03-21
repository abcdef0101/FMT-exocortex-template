#!/usr/bin/env bash
# Library-Class: entrypoint-helper

if [[ -n "${_EXTRACTOR_LIB_STATE_LOADED:-}" ]]; then
  return 0
fi
readonly _EXTRACTOR_LIB_STATE_LOADED=1

function extractor_is_work_hours() {
  local hour
  hour=$(date +%H)
  [[ "${hour}" -ge 7 ]] && [[ "${hour}" -le 23 ]]
}

function extractor_pending_captures_count() {
  local captures_file="${1}"

  [[ -f "${captures_file}" ]] || {
    printf '%s\n' "-1"
    return 0
  }

  local pending processed
  pending=$(grep -c '^### ' "${captures_file}" 2>/dev/null) || pending=0
  processed=$(grep -c '\[processed' "${captures_file}" 2>/dev/null) || processed=0
  printf '%s\n' "$((pending - processed))"
}
