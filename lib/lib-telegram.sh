#!/usr/bin/env bash
# Library-Class: entrypoint-helper

if [[ -n "${_LIB_TELEGRAM_LOADED:-}" ]]; then
  return 0
fi
readonly _LIB_TELEGRAM_LOADED=1

function iwe_telegram_load_env() {
  local env_file="${1}"
  if [[ -f "${env_file}" ]]; then
    iwe_validate_env_file "${env_file}" || return 1
    set -a
    # shellcheck source=/dev/null
    source "${env_file}"
    set +a
  fi
}

function iwe_telegram_available_templates() {
  local templates_dir="${1}"
  ls "${templates_dir}"/*.sh 2>/dev/null | xargs -I{} basename {} .sh | tr '\n' '|' | sed 's/|$//'
}

function iwe_telegram_send() {
  local telegram_bot_token="${1}"
  local telegram_chat_id="${2}"
  local text="${3}"
  local buttons="${4:-[]}"

  text="${text:0:4000}"
  local escaped_text json_body response ok
  escaped_text=$(printf '%s' "$text" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')

  if [[ "$buttons" == "[]" ]]; then
    json_body=$(printf '{"chat_id":"%s","text":%s,"parse_mode":"HTML","disable_web_page_preview":true}' \
      "$telegram_chat_id" "$escaped_text")
  else
    json_body=$(printf '{"chat_id":"%s","text":%s,"parse_mode":"HTML","disable_web_page_preview":true,"reply_markup":{"inline_keyboard":%s}}' \
      "$telegram_chat_id" "$escaped_text" "$buttons")
  fi

  response=$(curl --fail --max-time 10 --connect-timeout 5 -s -X POST "https://api.telegram.org/bot${telegram_bot_token}/sendMessage" \
    -H "Content-Type: application/json" \
    -d "$json_body")

  ok=$(echo "$response" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read()).get("ok",""))' 2>/dev/null || echo "")
  [[ "$ok" == "True" ]]
}
