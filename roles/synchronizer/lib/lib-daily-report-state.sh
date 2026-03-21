#!/usr/bin/env bash
# Library-Class: entrypoint-helper

if [[ -n "${_DAILY_REPORT_LIB_STATE_LOADED:-}" ]]; then
  return 0
fi
readonly _DAILY_REPORT_LIB_STATE_LOADED=1

function daily_report_check_ran() {
  local state_dir="${1}"
  local marker="${2}"
  local date_value="${3}"
  if [[ -f "${state_dir}/${marker}-${date_value}" ]]; then
    cat "${state_dir}/${marker}-${date_value}"
    return 0
  fi
  return 1
}

function daily_report_check_ran_week() {
  local state_dir="${1}"
  local marker="${2}"
  local week_value="${3}"
  if [[ -f "${state_dir}/${marker}-W${week_value}" ]]; then
    cat "${state_dir}/${marker}-W${week_value}"
    return 0
  fi
  return 1
}

function daily_report_check_interval() {
  local state_dir="${1}"
  local marker="${2}"
  local now_epoch="${3}"
  local marker_file ts ago
  marker_file="${state_dir}/${marker}-last"
  if [[ -f "${marker_file}" ]]; then
    ts=$(cat "${marker_file}")
    ago=$(( now_epoch - ts ))
    printf '%s сек назад\n' "${ago}"
    return 0
  fi
  return 1
}

function daily_report_archive_old_reports() {
  local report_dir="${1}"
  local archive_dir="${2}"
  local date_value="${3}"
  local log_callback="${4}"
  local old_report base_name

  for old_report in "${report_dir}"/SchedulerReport\ 20*.md; do
    [[ -f "${old_report}" ]] || continue
    base_name=$(basename "${old_report}")
    [[ "${base_name}" == *"${date_value}"* ]] && continue
    mv "${old_report}" "${archive_dir}/" 2>/dev/null || true
    "${log_callback}" "Archived: ${base_name}"
  done
}
