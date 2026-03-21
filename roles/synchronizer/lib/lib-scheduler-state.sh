#!/usr/bin/env bash
# Library-Class: entrypoint-helper

if [[ -n "${_SCHEDULER_LIB_STATE_LOADED:-}" ]]; then
  return 0
fi
readonly _SCHEDULER_LIB_STATE_LOADED=1

function scheduler_get_role_runner() {
  local roles_dir="${1}"
  local role="${2}"
  local yaml runner

  yaml="${roles_dir}/${role}/role.yaml"
  if [[ -f "${yaml}" ]]; then
    runner=$(grep '^runner:' "${yaml}" | sed 's/runner: *//' | tr -d '"' | tr -d "'")
    [[ -n "${runner}" ]] && {
      printf '%s\n' "${roles_dir}/${role}/${runner}"
      return 0
    }
  fi

  printf '%s\n' "${roles_dir}/${role}/scripts/${role}.sh"
}

function scheduler_ran_today() {
  local state_dir="${1}"
  local marker="${2}"
  local date_value="${3}"
  [[ -f "${state_dir}/${marker}-${date_value}" ]]
}

function scheduler_ran_this_week() {
  local state_dir="${1}"
  local marker="${2}"
  local week_value="${3}"
  [[ -f "${state_dir}/${marker}-W${week_value}" ]]
}

function scheduler_mark_done() {
  local state_dir="${1}"
  local marker="${2}"
  local date_value="${3}"
  printf '%s\n' "$(date '+%H:%M:%S')" > "${state_dir}/${marker}-${date_value}"
}

function scheduler_mark_done_week() {
  local state_dir="${1}"
  local marker="${2}"
  local date_value="${3}"
  local week_value="${4}"
  printf '%s %s\n' "${date_value}" "$(date '+%H:%M:%S')" > "${state_dir}/${marker}-W${week_value}"
}

function scheduler_last_run_seconds_ago() {
  local state_dir="${1}"
  local marker="${2}"
  local now_value="${3}"
  local marker_file prev

  marker_file="${state_dir}/${marker}-last"
  if [[ -f "${marker_file}" ]]; then
    prev=$(cat "${marker_file}")
    printf '%s\n' $(( now_value - prev ))
  else
    printf '%s\n' '999999'
  fi
}

function scheduler_mark_interval() {
  local state_dir="${1}"
  local marker="${2}"
  local now_value="${3}"
  printf '%s\n' "${now_value}" > "${state_dir}/${marker}-last"
}

function scheduler_cleanup_state() {
  local state_dir="${1}"
  find "${state_dir}" -name '*-202*' -mtime +7 -delete 2>/dev/null || true
}

function scheduler_show_status() {
  local state_dir="${1}"
  local date_value="${2}"
  local hour_value="${3}"
  local dow_value="${4}"
  local week_value="${5}"
  local now_value="${6}"

  echo "=== Exocortex Scheduler Status ==="
  echo "Date: ${date_value}  Hour: ${hour_value}  DOW: ${dow_value}  Week: W${week_value}"
  echo ""

  echo "--- Today's runs ---"
  local daily_files
  daily_files=$(ls "${state_dir}"/*-"${date_value}" 2>/dev/null || true)
  if [[ -n "${daily_files}" ]]; then
    echo "${daily_files}" | while read -r file_path; do
      echo "  $(basename "${file_path}"): $(cat "${file_path}")"
    done
  else
    echo "  (none)"
  fi

  echo ""
  echo "--- Interval markers ---"
  local interval_files ts ago
  interval_files=$(ls "${state_dir}"/*-last 2>/dev/null || true)
  if [[ -n "${interval_files}" ]]; then
    echo "${interval_files}" | while read -r file_path; do
      ts=$(cat "${file_path}")
      ago=$(( now_value - ts ))
      echo "  $(basename "${file_path}"): ${ago}s ago"
    done
  else
    echo "  (none)"
  fi

  echo ""
  echo "--- Week markers ---"
  local week_files
  week_files=$(ls "${state_dir}"/*-W"${week_value}" 2>/dev/null || true)
  if [[ -n "${week_files}" ]]; then
    echo "${week_files}" | while read -r file_path; do
      echo "  $(basename "${file_path}"): $(cat "${file_path}")"
    done
  else
    echo "  (none)"
  fi
}
