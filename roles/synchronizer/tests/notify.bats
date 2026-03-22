#!/usr/bin/env bats
# Тесты для roles/synchronizer/scripts/notify.sh
# Покрывает: _validate_env_file, send_telegram (mock curl), SKIP без токенов

load '../../../tests/test_helper/bats-support/load'
load '../../../tests/test_helper/bats-assert/load'
load 'test_helper/helpers'

REAL_SCRIPT="${BATS_TEST_DIRNAME}/../../../scripts/notify.sh"

setup() {
    TEST_DIR="$BATS_TEST_TMPDIR"
    BIN_DIR="$TEST_DIR/bin"
    SCRIPT_DIR_TMP="$TEST_DIR/scripts"
    TEMPLATES_DIR="$TEST_DIR/roles/synchronizer/scripts/templates"
    mkdir -p "$SCRIPT_DIR_TMP" "$TEMPLATES_DIR"
    cp "$REAL_SCRIPT" "$SCRIPT_DIR_TMP/notify.sh"
    cp -R "${BATS_TEST_DIRNAME}/../scripts/templates/." "$TEMPLATES_DIR/"
    SCRIPT="$SCRIPT_DIR_TMP/notify.sh"

    # Вычисляем ENV_FILE путь как делает скрипт
    local script_dir
    script_dir="$SCRIPT_DIR_TMP"
    local iwe_ws
    iwe_ws="$(cd "$script_dir/../.." && pwd)"
    ENV_DIR="$TEST_DIR/.$(basename "$iwe_ws")"
    ENV_FILE="$ENV_DIR/env"
    mkdir -p "$ENV_DIR" "$BIN_DIR"

    # Базовый env
    cat > "$ENV_FILE" <<EOF
WORKSPACE_DIR=$TEST_DIR/workspace
CLAUDE_PATH=/usr/local/bin/claude
GITHUB_USER=testuser
TELEGRAM_BOT_TOKEN=test-bot-token
TELEGRAM_CHAT_ID=123456789
EOF

    export PATH="$BIN_DIR:$PATH"
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
# notify.sh как целый скрипт — SKIP без токенов
# ---------------------------------------------------------------------------

@test "notify.sh: SKIP если TELEGRAM_BOT_TOKEN не задан" {
    # Env без токенов
    cat > "$ENV_FILE" <<EOF
WORKSPACE_DIR=$TEST_DIR/workspace
CLAUDE_PATH=/usr/local/bin/claude
GITHUB_USER=testuser
EOF
    # Нужен шаблон агента
    mkdir -p "$TEMPLATES_DIR"
    cat > "$TEMPLATES_DIR/synchronizer.sh" <<'EOF'
#!/usr/bin/env bash
build_message() { echo "test message"; }
get_buttons() { echo "[]"; }
EOF
    chmod +x "$TEMPLATES_DIR/synchronizer.sh"

    run env HOME="$TEST_DIR" bash "$SCRIPT" synchronizer code-scan
    assert_success
    assert_output --partial "SKIP"
}

@test "notify.sh: ошибка при вызове без аргументов" {
    run env HOME="$TEST_DIR" bash "$SCRIPT"
    assert_failure
    assert_output --partial "укажи агента"
}

@test "notify.sh: ошибка при одном аргументе (без сценария)" {
    mkdir -p "$TEMPLATES_DIR"
    cat > "$TEMPLATES_DIR/synchronizer.sh" <<'EOF'
#!/usr/bin/env bash
build_message() { echo "test"; }
EOF
    chmod +x "$TEMPLATES_DIR/synchronizer.sh"

    run env HOME="$TEST_DIR" bash "$SCRIPT" synchronizer
    assert_failure
    assert_output --partial "укажи сценарий"
}
