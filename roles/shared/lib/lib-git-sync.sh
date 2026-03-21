#!/usr/bin/env bash
# Library-Class: entrypoint-helper

if [[ -n "${_ROLES_SHARED_LIB_GIT_SYNC_LOADED:-}" ]]; then
  return 0
fi
readonly _ROLES_SHARED_LIB_GIT_SYNC_LOADED=1

function iwe_sync_strategy_extraction_report() {
  local strategy_dir="${1}"
  local log_file="${2}"
  local commit_date="${3}"

  [[ -d "${strategy_dir}/.git" ]] || return 0

  git -C "${strategy_dir}" reset --quiet 2>/dev/null || true
  git -C "${strategy_dir}" add inbox/captures.md inbox/extraction-reports/ >> "${log_file}" 2>&1 || true

  if ! git -C "${strategy_dir}" diff --cached --quiet 2>/dev/null; then
    git -C "${strategy_dir}" commit -m "inbox-check: extraction report ${commit_date}" >> "${log_file}" 2>&1
  fi

  if ! git -C "${strategy_dir}" diff --quiet origin/main..HEAD 2>/dev/null; then
    git -C "${strategy_dir}" push >> "${log_file}" 2>&1
  fi
}
