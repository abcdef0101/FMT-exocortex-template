#!/usr/bin/env bash
# Library-Class: entrypoint-helper

if [[ -n "${_DT_MERGE_LIB_LOADED:-}" ]]; then
  return 0
fi
readonly _DT_MERGE_LIB_LOADED=1

function dt_merge_json_payload() {
  local waka_json="${1}"
  local git_json="${2}"
  local sessions_json="${3}"
  local wp_json="${4}"
  local health_json="${5}"

  python3 -c "
import json

waka = json.loads('''${waka_json}''')
git = json.loads('''${git_json}''')
sessions = json.loads('''${sessions_json}''')
wp = json.loads('''${wp_json}''')
health = json.loads('''${health_json}''')

result = {
    '2_6_coding': waka,
    '2_7_iwe': {**git, **sessions, **wp, **health},
}
print(json.dumps(result, indent=2, ensure_ascii=False))
" 2>/dev/null
}

function dt_write_payload() {
  local script_dir="${1}"
  local dt_user_id="${2}"
  local merged_json="${3}"
  local log_file="${4}"

  dt_log "${log_file}" "Writing to Neon (user_id=${dt_user_id})..."
  python3 "${script_dir}/dt-collect-neon.py" "${dt_user_id}" "${merged_json}" 2>>"${log_file}"
}
