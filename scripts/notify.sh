#!/usr/bin/env bash
# notify.sh — единый dispatch уведомлений экзокортекса
# Targets: Linux, macOS

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/templates"

# shellcheck source=lib/lib-env.sh
source "${SCRIPT_DIR}/../lib/lib-env.sh"

# shellcheck source=lib/lib-telegram.sh
source "${SCRIPT_DIR}/../lib/lib-telegram.sh"

_repo_root="$(iwe_find_repo_root "${SCRIPT_DIR}")" \
  || { echo "ERROR: Cannot resolve repo root from ${SCRIPT_DIR}" >&2; exit 1; }
ENV_FILE="$(iwe_env_file_from_repo_root "${_repo_root}")"
unset _repo_root

AVAILABLE=$(iwe_telegram_available_templates "$TEMPLATES_DIR")
AGENT="${1:?Ошибка: укажи агента (${AVAILABLE:-нет шаблонов})}"
SCENARIO="${2:?Ошибка: укажи сценарий}"

iwe_telegram_load_env "$ENV_FILE" || exit 1

if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]] || [[ -z "${TELEGRAM_CHAT_ID:-}" ]]; then
  echo "SKIP: TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID not set (configure ~/.config/aist/env)"
  exit 0
fi

TEMPLATE="$TEMPLATES_DIR/$AGENT.sh"
if [[ ! -f "$TEMPLATE" ]]; then
  echo "ERROR: Template not found: $TEMPLATE" >&2
  exit 1
fi

source "$TEMPLATE"

MESSAGE=$(build_message "$SCENARIO")
BUTTONS=$(build_buttons "$SCENARIO" 2>/dev/null || echo "[]")

if [[ -n "$MESSAGE" ]]; then
  if iwe_telegram_send "$TELEGRAM_BOT_TOKEN" "$TELEGRAM_CHAT_ID" "$MESSAGE" "$BUTTONS"; then
    echo "Telegram notification sent: $AGENT/$SCENARIO"
  else
    echo "Telegram send FAILED: $AGENT/$SCENARIO"
  fi
else
  echo "Empty message for $AGENT/$SCENARIO, skip"
fi
