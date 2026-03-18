#!/usr/bin/env bash
# notify.sh — единый dispatch уведомлений экзокортекса
# Targets: Linux, macOS
#
# Exit codes:
#   0 — успех
#   1 — ошибка
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/templates"
ENV_FILE="$HOME/.config/aist/env"

AVAILABLE=$(ls "$TEMPLATES_DIR"/*.sh 2>/dev/null | xargs -I{} basename {} .sh | tr '\n' '|' | sed 's/|$//')
AGENT="${1:?Ошибка: укажи агента (${AVAILABLE:-нет шаблонов})}"
SCENARIO="${2:?Ошибка: укажи сценарий}"

# Загрузка env
_validate_env_file() {
    local filepath="${1}"
    if grep -qE '^\s*(eval|source|\.)[ \t]' "${filepath}" 2>/dev/null; then
        echo "ERROR: env file contains dangerous patterns: ${filepath}" >&2
        exit 1
    fi
}

if [ -f "$ENV_FILE" ]; then
    _validate_env_file "$ENV_FILE"
    set -a
    source "$ENV_FILE"
    set +a
fi

# Проверка env vars
if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
    echo "SKIP: TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID not set (configure ~/.config/aist/env)"
    exit 0
fi

# Отправка в Telegram
send_telegram() {
    local text="$1"
    local buttons="${2:-[]}"

    text="${text:0:4000}"

    local escaped_text
    escaped_text=$(printf '%s' "$text" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')

    local json_body
    if [ "$buttons" = "[]" ]; then
        json_body=$(printf '{"chat_id":"%s","text":%s,"parse_mode":"HTML","disable_web_page_preview":true}' \
            "$TELEGRAM_CHAT_ID" "$escaped_text")
    else
        json_body=$(printf '{"chat_id":"%s","text":%s,"parse_mode":"HTML","disable_web_page_preview":true,"reply_markup":{"inline_keyboard":%s}}' \
            "$TELEGRAM_CHAT_ID" "$escaped_text" "$buttons")
    fi

    local response
    response=$(curl --fail --max-time 10 --connect-timeout 5 -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "$json_body")

    local ok
    ok=$(echo "$response" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read()).get("ok",""))' 2>/dev/null || echo "")

    if [ "$ok" = "True" ]; then
        echo "Telegram notification sent: $AGENT/$SCENARIO"
    else
        echo "Telegram send FAILED: $AGENT/$SCENARIO"
        echo "Response: $response"
    fi
}

# Загружаем шаблон агента
TEMPLATE="$TEMPLATES_DIR/$AGENT.sh"
if [ ! -f "$TEMPLATE" ]; then
    echo "ERROR: Template not found: $TEMPLATE" >&2
    exit 1
fi

source "$TEMPLATE"

MESSAGE=$(build_message "$SCENARIO")
BUTTONS=$(build_buttons "$SCENARIO" 2>/dev/null || echo "[]")

if [ -n "$MESSAGE" ]; then
    send_telegram "$MESSAGE" "$BUTTONS"
else
    echo "Empty message for $AGENT/$SCENARIO, skip"
fi
