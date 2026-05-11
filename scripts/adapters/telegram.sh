#!/usr/bin/env bash
# Adapter: Telegram
# Requires: python3, curl
# Targets: inherited from caller

_TELEGRAM_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/lib-env.sh
source "${_TELEGRAM_ADAPTER_DIR}/../../lib/lib-env.sh"
# shellcheck source=lib/lib-telegram.sh
source "${_TELEGRAM_ADAPTER_DIR}/../../lib/lib-telegram.sh"
unset _TELEGRAM_ADAPTER_DIR

adapter_enabled() {
  [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]] && [[ -n "${TELEGRAM_CHAT_ID:-}" ]]
}

adapter_min_level() { printf 'notice'; }

adapter_send() {
  local title="${1}"
  local message="${2}"
  local full_text
  full_text="$(printf '<b>%s</b>\n\n%s' "${title}" "${message}")"
  if iwe_telegram_send "${TELEGRAM_BOT_TOKEN}" "${TELEGRAM_CHAT_ID}" "${full_text}" "[]"; then
    printf 'Sent via telegram\n'
  else
    printf 'Telegram send FAILED\n' >&2
    return 1
  fi
}
