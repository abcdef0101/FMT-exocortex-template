#!/usr/bin/env bash
# Library-Class: entrypoint-helper

if [[ -n "${_SCHEDULER_LIB_DISPATCH_LOADED:-}" ]]; then
  return 0
fi
readonly _SCHEDULER_LIB_DISPATCH_LOADED=1

function scheduler_pre_archive_dayplan() {
  local workspace_dir="${1}"
  local date_value="${2}"
  local log_callback="${3}"

  local strategy_dir archive_dir moved fname dayplan
  strategy_dir="${workspace_dir}/DS-strategy"
  archive_dir="${strategy_dir}/archive/day-plans"
  moved=0

  mkdir -p "${archive_dir}"

  for dayplan in "${strategy_dir}/current"/DayPlan\ 20*.md; do
    [[ -f "${dayplan}" ]] || continue
    fname=$(basename "${dayplan}")
    [[ "${fname}" == *"${date_value}"* ]] && continue
    git -C "${strategy_dir}" mv "${dayplan}" "${archive_dir}/" 2>/dev/null || mv "${dayplan}" "${archive_dir}/"
    moved=$((moved + 1))
    "${log_callback}" "pre-archive: moved ${fname} → archive/day-plans/"
  done

  if [[ "${moved}" -gt 0 ]]; then
    git -C "${strategy_dir}" pull --rebase 2>/dev/null || true
    git -C "${strategy_dir}" add current/ archive/day-plans/ 2>/dev/null || true
    git -C "${strategy_dir}" commit -m "chore: archive ${moved} old DayPlan(s)" 2>/dev/null || true
    git -C "${strategy_dir}" push 2>/dev/null || true
    "${log_callback}" "pre-archive: committed and pushed (${moved} file(s))"
  fi
}

function scheduler_run_and_mark_daily() {
  local script_path="${1}"
  local script_args="${2}"
  local state_dir="${3}"
  local marker="${4}"
  local date_value="${5}"
  local log_file="${6}"
  local log_callback="${7}"
  local warn_message="${8}"

  # shellcheck disable=SC2086
  if "${script_path}" ${script_args} >> "${log_file}" 2>&1; then
    scheduler_mark_done "${state_dir}" "${marker}" "${date_value}"
    return 0
  fi

  "${log_callback}" "${warn_message}"
  return 1
}

function scheduler_run_and_mark_weekly() {
  local script_path="${1}"
  local script_args="${2}"
  local state_dir="${3}"
  local marker="${4}"
  local date_value="${5}"
  local week_value="${6}"
  local log_file="${7}"
  local log_callback="${8}"
  local warn_message="${9}"

  # shellcheck disable=SC2086
  if "${script_path}" ${script_args} >> "${log_file}" 2>&1; then
    scheduler_mark_done_week "${state_dir}" "${marker}" "${date_value}" "${week_value}"
    return 0
  fi

  "${log_callback}" "${warn_message}"
  return 1
}
