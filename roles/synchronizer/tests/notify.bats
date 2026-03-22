#!/usr/bin/env bats
# Тесты для scripts/notify.sh (Observer dispatcher)
# Покрывает: _validate_env_file, send_telegram (mock curl), Observer interface

load '../../../tests/test_helper/bats-support/load'
load '../../../tests/test_helper/bats-assert/load'
load 'test_helper/helpers'

REAL_SCRIPT="${BATS_TEST_DIRNAME}/../../../scripts/notify.sh"

setup() {
    TEST_DIR="$BATS_TEST_TMPDIR"
    BIN_DIR="$TEST_DIR/bin"
    SCRIPT_DIR_TMP="$TEST_DIR/scripts"
    CURL_LOG="$TEST_DIR/curl.log"
    mkdir -p "$SCRIPT_DIR_TMP" "$BIN_DIR"
    cp "$REAL_SCRIPT" "$SCRIPT_DIR_TMP/notify.sh"
    mkdir -p "$SCRIPT_DIR_TMP/adapters"
    cp -R "${BATS_TEST_DIRNAME}/../../../scripts/adapters/." "$SCRIPT_DIR_TMP/adapters/"
    chmod +x "$SCRIPT_DIR_TMP/adapters/"*.sh
    SCRIPT="$SCRIPT_DIR_TMP/notify.sh"

    # lib/ нужен для notify.sh: source "${SCRIPT_DIR}/../lib/lib-env.sh"
    mkdir -p "$TEST_DIR/lib"
    cp -R "${BATS_TEST_DIRNAME}/../../../lib/." "$TEST_DIR/lib/"

    # CLAUDE.md + memory — нужны iwe_find_repo_root из TEST_DIR/scripts
    cat > "$TEST_DIR/CLAUDE.md" <<'EOFMD'
# test
EOFMD
    mkdir -p "$TEST_DIR/memory"

    # Вычисляем ENV_FILE путь как делает скрипт
    # repo_root = TEST_DIR, workspace_dir = dirname(TEST_DIR), env = HOME/.basename/env
    local iwe_ws
    iwe_ws="$(cd "$TEST_DIR/.." && pwd)"
    ENV_DIR="$TEST_DIR/.$(basename "$iwe_ws")"
    ENV_FILE="$ENV_DIR/env"
    mkdir -p "$ENV_DIR"

    # Базовый env
    cat > "$ENV_FILE" <<EOF
WORKSPACE_DIR=$TEST_DIR/workspace
CLAUDE_PATH=/usr/local/bin/claude
GITHUB_USER=testuser
TELEGRAM_BOT_TOKEN=test-bot-token
TELEGRAM_CHAT_ID=123456789
EOF

    export PATH="$BIN_DIR:$PATH"
    export CURL_LOG
}

# ---------------------------------------------------------------------------
# _validate_env_file (inline из notify.sh)
# ---------------------------------------------------------------------------

_load_validate() {
    source /dev/stdin <<'EOF'
_validate_env_file() {
    local filepath="${1}"
    if grep -qE '^\s*(eval|source|\.)[ \t]' "${filepath}" 2>/dev/null; then
        echo "ERROR: env file contains dangerous patterns: ${filepath}" >&2
        exit 1
    fi
}
EOF
}

@test "_validate_env_file: успех с корректным env" {
    _load_validate
    run _validate_env_file "$ENV_FILE"
    assert_success
}

@test "_validate_env_file: ошибка при eval-инъекции" {
    _load_validate
    printf 'KEY=value\neval "rm -rf /"\n' > "$TEST_DIR/danger.env"
    run _validate_env_file "$TEST_DIR/danger.env"
    assert_failure
    assert_output --partial "dangerous patterns"
}

@test "_validate_env_file: ошибка при source-инъекции" {
    _load_validate
    printf 'KEY=value\nsource /etc/passwd\n' > "$TEST_DIR/source.env"
    run _validate_env_file "$TEST_DIR/source.env"
    assert_failure
}

@test "_validate_env_file: ошибка при dot-инъекции" {
    _load_validate
    printf 'KEY=value\n. /etc/malicious\n' > "$TEST_DIR/dot.env"
    run _validate_env_file "$TEST_DIR/dot.env"
    assert_failure
}

# ---------------------------------------------------------------------------
# send_telegram с mock curl
# ---------------------------------------------------------------------------

_load_send_telegram() {
    source /dev/stdin <<'EOF'
send_telegram() {
    local text="$1"
    local buttons="${2:-[]}"
    text="${text:0:4000}"
    local escaped_text
    escaped_text=$(printf '%s' "$text" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')
    local json_body
    if [ "$buttons" = "[]" ]; then
        json_body=$(printf '{"chat_id":"%s","text":%s,"parse_mode":"HTML"}' \
            "${TELEGRAM_CHAT_ID}" "$escaped_text")
    fi
    local response
    response=$(curl --fail --max-time 10 --connect-timeout 5 -s -X POST \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "$json_body")
    local ok
    ok=$(echo "$response" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read()).get("ok",""))' 2>/dev/null || echo "")
    if [ "$ok" = "True" ]; then
        echo "Telegram notification sent"
    else
        echo "Telegram send FAILED"
        echo "Response: $response"
    fi
}
EOF
}

@test "send_telegram: успех при ok=True" {
    cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
echo '{"ok": true}'
EOF
    chmod +x "$BIN_DIR/curl"
    export TELEGRAM_BOT_TOKEN="test-token"
    export TELEGRAM_CHAT_ID="123456789"
    _load_send_telegram

    run send_telegram "Тест уведомления"
    assert_success
    assert_output --partial "notification sent"
}

@test "send_telegram: FAILED при ok=false" {
    cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
echo '{"ok": false, "description": "Bad Request"}'
EOF
    chmod +x "$BIN_DIR/curl"
    export TELEGRAM_BOT_TOKEN="test-token"
    export TELEGRAM_CHAT_ID="123456789"
    _load_send_telegram

    run send_telegram "Тест уведомления"
    assert_success  # функция не падает
    assert_output --partial "FAILED"
}

@test "send_telegram: обрезает текст до 4000 символов" {
    export TELEGRAM_BOT_TOKEN="test-token"
    export TELEGRAM_CHAT_ID="123456789"
    _load_send_telegram

    local long_text
    long_text=$(printf '%05001d' 0 | tr '0' 'x')  # 5001 символ

    # Шпион: пишем тело запроса в файл
    cat > "$BIN_DIR/curl" <<EOF
#!/usr/bin/env bash
# Найти -d аргумент
while [[ "\$1" != "-d" && "\$#" -gt 0 ]]; do shift; done
echo "\$2" > "$TEST_DIR/request_body"
    echo '{"ok": true}'
EOF
    chmod +x "$BIN_DIR/curl"

    send_telegram "$long_text"
    run python3 -c "
import json
with open('$TEST_DIR/request_body') as f:
    body = json.load(f)
text = body['text']  # это JSON-строка
print(len(text))
"
    assert_success
    assert [ "$output" -le 4000 ]
}

# ---------------------------------------------------------------------------
# notify.sh как целый скрипт — Observer interface
# ---------------------------------------------------------------------------

@test "notify.sh: пропускает Telegram без токена" {
    # Env без Telegram-токенов
    cat > "$ENV_FILE" <<EOF
WORKSPACE_DIR=$TEST_DIR/workspace
CLAUDE_PATH=/usr/local/bin/claude
GITHUB_USER=testuser
EOF

    run env HOME="$TEST_DIR" bash "$SCRIPT" "Test Title" "Test Message" notice
    assert_success
    # Curl не вызывался — Telegram-адаптер отключён
    run test -f "$CURL_LOG"
    assert_failure
}

@test "notify.sh: ошибка при вызове без аргументов" {
    run env HOME="$TEST_DIR" bash "$SCRIPT"
    assert_failure
    assert_output --partial "укажи заголовок"
}

@test "notify.sh: ошибка при одном аргументе (без тела сообщения)" {
    run env HOME="$TEST_DIR" bash "$SCRIPT" "Title Only"
    assert_failure
    assert_output --partial "укажи тело сообщения"
}

@test "notify.sh: отправляет через Telegram при наличии токенов" {
    cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_LOG"
printf '{"ok": true}'
EOF
    chmod +x "$BIN_DIR/curl"

    run env HOME="$TEST_DIR" bash "$SCRIPT" "Test Title" "Test Message" notice
    assert_success
    assert_output --partial "Sent via telegram"
    run grep 'api.telegram.org' "$CURL_LOG"
    assert_success
}
