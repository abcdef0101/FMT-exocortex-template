#!/usr/bin/env bats
# Тесты для scripts/notify.sh (Observer dispatcher, ADR-014)
# Покрывает: lib-env.sh, lib-telegram.sh, notify.sh Observer interface

load '../../../tests/test_helper/bats-support/load'
load '../../../tests/test_helper/bats-assert/load'

setup() {
    TEST_DIR="$BATS_TEST_TMPDIR"
    BIN_DIR="$TEST_DIR/bin"
    mkdir -p "$BIN_DIR"
    export PATH="$BIN_DIR:$PATH"
}

# ===========================================================================
# iwe_validate_env_file (lib/lib-env.sh)
# ===========================================================================

@test "iwe_validate_env_file: успех с корректным env" {
    source "${BATS_TEST_DIRNAME}/../../../lib/lib-env.sh"
    local env_file="$TEST_DIR/good.env"
    printf 'KEY=value\nOTHER=val2\n' > "$env_file"
    run iwe_validate_env_file "$env_file"
    assert_success
}

@test "iwe_validate_env_file: ошибка при eval-инъекции" {
    source "${BATS_TEST_DIRNAME}/../../../lib/lib-env.sh"
    local env_file="$TEST_DIR/bad.env"
    printf 'KEY=value\neval "rm -rf /"\n' > "$env_file"
    run iwe_validate_env_file "$env_file"
    assert_failure
    assert_output --partial "dangerous patterns"
}

@test "iwe_validate_env_file: ошибка при source-инъекции" {
    source "${BATS_TEST_DIRNAME}/../../../lib/lib-env.sh"
    local env_file="$TEST_DIR/src.env"
    printf 'KEY=value\nsource /etc/passwd\n' > "$env_file"
    run iwe_validate_env_file "$env_file"
    assert_failure
}

@test "iwe_validate_env_file: ошибка при dot-инъекции" {
    source "${BATS_TEST_DIRNAME}/../../../lib/lib-env.sh"
    local env_file="$TEST_DIR/dot.env"
    printf 'KEY=value\n. /etc/malicious\n' > "$env_file"
    run iwe_validate_env_file "$env_file"
    assert_failure
}

# ===========================================================================
# iwe_telegram_send (lib/lib-telegram.sh)
# ===========================================================================

@test "iwe_telegram_send: успех при ok=True" {
    cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
echo '{"ok":true}'
EOF
    chmod +x "$BIN_DIR/curl"
    source "${BATS_TEST_DIRNAME}/../../../lib/lib-telegram.sh"

    run iwe_telegram_send "tok" "123" "Hello" "[]"
    assert_success
}

@test "iwe_telegram_send: FAILED при ok=False" {
    cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
echo '{"ok":false,"description":"Bad Request"}'
EOF
    chmod +x "$BIN_DIR/curl"
    source "${BATS_TEST_DIRNAME}/../../../lib/lib-telegram.sh"

    run iwe_telegram_send "tok" "123" "Hello" "[]"
    assert_failure
}

@test "iwe_telegram_send: обрезает текст до 4000 символов" {
    cat > "$BIN_DIR/curl" <<EOF
#!/usr/bin/env bash
while [ \$# -gt 0 ]; do
  if [ "\$1" = "-d" ]; then
    printf '%s' "\$2" > "$BATS_TEST_TMPDIR/telegram_request.json"
  fi
  shift
done
echo '{"ok":true}'
EOF
    chmod +x "$BIN_DIR/curl"
    source "${BATS_TEST_DIRNAME}/../../../lib/lib-telegram.sh"

    local long_text
    long_text=$(printf '%05001d' 0 | tr '0' 'x')
    run iwe_telegram_send "tok" "123" "$long_text" "[]"
    assert_success
    run python3 - "$BATS_TEST_TMPDIR/telegram_request.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding='utf-8') as fh:
    data = json.load(fh)
assert len(data['text']) == 4000
PY
    assert_success
}

# ===========================================================================
# notify.sh — базовые ошибки
# ===========================================================================

@test "notify.sh: ошибка при вызове без аргументов" {
    run bash "${BATS_TEST_DIRNAME}/../../../scripts/notify.sh"
    assert_failure
    assert_output --partial "укажи заголовок"
}

@test "notify.sh: ошибка при одном аргументе" {
    run bash "${BATS_TEST_DIRNAME}/../../../scripts/notify.sh" "Title Only"
    assert_failure
    assert_output --partial "укажи тело сообщения"
}

@test "notify.sh: неизвестный level выводит предупреждение" {
    run bash "${BATS_TEST_DIRNAME}/../../../scripts/notify.sh" "T" "M" "badlevel"
    assert_success
    assert_output --partial 'unknown notify level'
}

# ===========================================================================
# notify.sh — интеграция с адаптерами
# ===========================================================================

_make_env() {
    local token="${1:-}"
    local chat="${2:-}"
    local file="$TEST_DIR/env"

    cat > "$file" <<EOF
TELEGRAM_BOT_TOKEN=$token
TELEGRAM_CHAT_ID=$chat
EOF
    echo "$file"
}

@test "notify.sh: пропускает Telegram без токенов" {
    local env_file
    env_file="$(_make_env "" "")"
    cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
echo '{"ok":true}'
EOF
    chmod +x "$BIN_DIR/curl"

    run env IWE_NOTIFY_ENV_FILE="$env_file" \
        bash "${BATS_TEST_DIRNAME}/../../../scripts/notify.sh" "T" "M" notice
    assert_success
    refute_output --partial "Sent via telegram"
}

@test "notify.sh: отправляет через Telegram" {
    local env_file
    env_file="$(_make_env "test-token" "12345")"
    cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
echo '{"ok":true}'
EOF
    chmod +x "$BIN_DIR/curl"

    run env IWE_NOTIFY_ENV_FILE="$env_file" \
        bash "${BATS_TEST_DIRNAME}/../../../scripts/notify.sh" "T" "M" notice
    assert_success
    assert_output --partial "Sent via telegram"
}

@test "notify.sh: level=info не проходит Telegram (min=notice)" {
    local env_file
    env_file="$(_make_env "test-token" "12345")"
    cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
echo '{"ok":true}'
EOF
    chmod +x "$BIN_DIR/curl"

    run env IWE_NOTIFY_ENV_FILE="$env_file" \
        bash "${BATS_TEST_DIRNAME}/../../../scripts/notify.sh" "T" "M" info
    assert_success
    refute_output --partial "Sent via telegram"
}

@test "notify.sh: level=alert проходит Telegram (min=notice)" {
    local env_file
    env_file="$(_make_env "test-token" "12345")"
    cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
echo '{"ok":true}'
EOF
    chmod +x "$BIN_DIR/curl"

    run env IWE_NOTIFY_ENV_FILE="$env_file" \
        bash "${BATS_TEST_DIRNAME}/../../../scripts/notify.sh" "T" "M" alert
    assert_success
    assert_output --partial "Sent via telegram"
}

@test "notify.sh: IWE_NOTIFY_ENV_FILE приоритет над auto-discovery" {
    cat > "$BIN_DIR/curl" <<EOF
#!/usr/bin/env bash
echo "\$*" > "$TEST_DIR/curl_args"
echo '{"ok":true}'
EOF
    chmod +x "$BIN_DIR/curl"

    mkdir -p "$TEST_DIR/repo/memory" "$TEST_DIR/repo/scripts/adapters" "$TEST_DIR/repo/lib"
    touch "$TEST_DIR/repo/CLAUDE.md"
    cp "${BATS_TEST_DIRNAME}/../../../scripts/notify.sh" "$TEST_DIR/repo/scripts/notify.sh"
    cp -R "${BATS_TEST_DIRNAME}/../../../scripts/adapters/"* "$TEST_DIR/repo/scripts/adapters/"
    cp -R "${BATS_TEST_DIRNAME}/../../../lib/"* "$TEST_DIR/repo/lib/"

    local auto_env_dir="$TEST_DIR/.$(basename "$TEST_DIR")"
    mkdir -p "$auto_env_dir"
    printf 'TELEGRAM_BOT_TOKEN=auto-token\nTELEGRAM_CHAT_ID=22222\n' > "$auto_env_dir/env"

    local env_file="$TEST_DIR/priority.env"
    printf 'TELEGRAM_BOT_TOKEN=custom-token\nTELEGRAM_CHAT_ID=11111\n' > "$env_file"

    env HOME="$TEST_DIR" IWE_NOTIFY_ENV_FILE="$env_file" \
        bash "$TEST_DIR/repo/scripts/notify.sh" "T" "M" notice

    run grep 'custom-token' "$TEST_DIR/curl_args"
    assert_success
    run grep -q 'auto-token' "$TEST_DIR/curl_args"
    assert_failure
}

@test "notify.sh: log.sh адаптер пишет в файл" {
    local env_file
    env_file="$(_make_env "" "")"

    local saved_home="$HOME"
    export HOME="$BATS_TEST_TMPDIR/log-notify-test"

    run env IWE_NOTIFY_ENV_FILE="$env_file" \
        bash "${BATS_TEST_DIRNAME}/../../../scripts/notify.sh" "TestTitle" "TestMessage" info
    assert_success

    local today_log="$HOME/.local/state/logs/notify/$(date +%Y-%m-%d).log"
    run grep 'TestTitle' "$today_log"
    assert_success
    export HOME="$saved_home"
}

@test "notify.sh: disabled адаптер не отправляет" {
    local env_file
    env_file="$(_make_env "" "")"

    run env IWE_NOTIFY_ENV_FILE="$env_file" \
        bash "${BATS_TEST_DIRNAME}/../../../scripts/notify.sh" "T" "M" notice
    assert_success
    refute_output --partial "Sent via telegram"
}

# ===========================================================================
# notify.sh — auto-discovery fallback, counters, edge cases
# ===========================================================================

@test "notify.sh: auto-discovery fallback (без IWE_NOTIFY_ENV_FILE)" {
    # Создаём фейковый repo для iwe_find_repo_root
    mkdir -p "$TEST_DIR/memory"
    touch "$TEST_DIR/CLAUDE.md"

    # Копируем notify.sh и зависимости в тестовую структуру
    mkdir -p "$TEST_DIR/scripts/adapters"
    cp "${BATS_TEST_DIRNAME}/../../../scripts/notify.sh" "$TEST_DIR/scripts/"
    cp -R "${BATS_TEST_DIRNAME}/../../../scripts/adapters/"* "$TEST_DIR/scripts/adapters/"
    mkdir -p "$TEST_DIR/lib"
    cp -R "${BATS_TEST_DIRNAME}/../../../lib/"* "$TEST_DIR/lib/"

    # Env file для auto-discovery
    local iwe_ws
    iwe_ws="$(cd "$TEST_DIR/.." && pwd)"
    local env_dir="$TEST_DIR/.$(basename "$iwe_ws")"
    mkdir -p "$env_dir"
    printf 'TELEGRAM_BOT_TOKEN=auto-tok\nTELEGRAM_CHAT_ID=99999\n' > "$env_dir/env"

    cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
echo '{"ok":true}'
EOF
    chmod +x "$BIN_DIR/curl"

    run env HOME="$TEST_DIR" bash "$TEST_DIR/scripts/notify.sh" \
        "AutoDiscovery" "Test" notice
    assert_success
    assert_output --partial "Sent via telegram"
}

@test "notify.sh: _dispatched и _sent при всех 4 адаптерах" {
    local env_file
    env_file="$(_make_env "tok" "123")"

    cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
echo '{"ok":true}'
EOF
    chmod +x "$BIN_DIR/curl"

    local saved_home="$HOME"
    export HOME="$BATS_TEST_TMPDIR/log-counters-test"

    # log.sh всегда enabled + telegram.sh enabled = _dispatched=4, _sent=2
    # slack.sh и email.sh disabled (no env vars)
    run env IWE_NOTIFY_ENV_FILE="$env_file" \
        bash "${BATS_TEST_DIRNAME}/../../../scripts/notify.sh" "CounterTest" "Msg" notice
    assert_success
    assert_output --partial "Sent via telegram"
    # log.sh should have written
    run test -f "$HOME/.local/state/logs/notify/$(date +%Y-%m-%d).log"
    assert_success
    export HOME="$saved_home"
}

@test "notify.sh: WARN при отсутствии файлов адаптеров" {
    local env_file
    env_file="$(_make_env "" "")"
    local empty_adapters="$TEST_DIR/adapters"
    mkdir -p "$empty_adapters"

    # Копируем notify.sh во временную директорию, но без адаптеров
    local tmp_notify="$TEST_DIR/notify.sh"
    cp "${BATS_TEST_DIRNAME}/../../../scripts/notify.sh" "$tmp_notify"
    # Патчим путь к adapters/ на пустую директорию
    sed "s|ADAPTERS_DIR=\"\${SCRIPT_DIR}/adapters\"|ADAPTERS_DIR=\"$empty_adapters\"|" "$tmp_notify" > "$tmp_notify.tmp" && mv "$tmp_notify.tmp" "$tmp_notify"
    # Патчим путь к lib-ам
    sed "s|source \"\${SCRIPT_DIR}/../lib/lib-env.sh\"|source \"${BATS_TEST_DIRNAME}/../../../lib/lib-env.sh\"|" "$tmp_notify" > "$tmp_notify.tmp" && mv "$tmp_notify.tmp" "$tmp_notify"

    run env IWE_NOTIFY_ENV_FILE="$env_file" bash "$tmp_notify" "T" "M" notice
    assert_success
    assert_output --partial "No adapters found"
}
