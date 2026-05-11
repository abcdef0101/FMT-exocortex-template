#!/usr/bin/env bats
# Тесты для scripts/adapters/ (ADR-014)

load '../../../tests/test_helper/bats-support/load'
load '../../../tests/test_helper/bats-assert/load'

ADAPTERS="${BATS_TEST_DIRNAME}/../../../scripts/adapters"

setup() {
    BIN_DIR="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$BIN_DIR"
    export PATH="$BIN_DIR:$PATH"
}

# ===========================================================================
# telegram.sh
# ===========================================================================

@test "telegram: adapter_enabled=true при TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID" {
    source "$ADAPTERS/telegram.sh"
    export TELEGRAM_BOT_TOKEN="tok"
    export TELEGRAM_CHAT_ID="123"
    run adapter_enabled
    assert_success
}

@test "telegram: adapter_enabled=false без токенов" {
    source "$ADAPTERS/telegram.sh"
    unset TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID
    run adapter_enabled
    assert_failure
}

@test "telegram: adapter_enabled=false без TELEGRAM_CHAT_ID" {
    source "$ADAPTERS/telegram.sh"
    export TELEGRAM_BOT_TOKEN="tok"
    unset TELEGRAM_CHAT_ID
    run adapter_enabled
    assert_failure
}

@test "telegram: adapter_min_level = notice" {
    source "$ADAPTERS/telegram.sh"
    run adapter_min_level
    assert_success
    assert_output "notice"
}

@test "telegram: adapter_send отправляет сообщение" {
    cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
echo '{"ok":true}'
EOF
    chmod +x "$BIN_DIR/curl"
    source "$ADAPTERS/telegram.sh"
    export TELEGRAM_BOT_TOKEN="tok"
    export TELEGRAM_CHAT_ID="123"

    run adapter_send "TestTitle" "TestMessage"
    assert_success
    assert_output --partial "Sent via telegram"
}

@test "telegram: adapter_send FAILED при ошибке API" {
    cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
echo '{"ok":false}'
exit 0
EOF
    chmod +x "$BIN_DIR/curl"
    source "$ADAPTERS/telegram.sh"
    export TELEGRAM_BOT_TOKEN="tok"
    export TELEGRAM_CHAT_ID="123"

    run adapter_send "TestTitle" "TestMessage"
    assert_failure
    assert_output --partial "FAILED"
}

# ===========================================================================
# log.sh
# ===========================================================================

@test "log: adapter_enabled всегда true" {
    source "$ADAPTERS/log.sh"
    run adapter_enabled
    assert_success
}

@test "log: adapter_min_level = info" {
    source "$ADAPTERS/log.sh"
    run adapter_min_level
    assert_success
    assert_output "info"
}

@test "log: adapter_send пишет запись в файл" {
    source "$ADAPTERS/log.sh"
    local saved_home="$HOME"
    export HOME="$BATS_TEST_TMPDIR/log-test"
    adapter_send "LogTitle" "LogMessage"

    local today_log="$HOME/.local/state/logs/notify/$(date +%Y-%m-%d).log"
    run grep 'LogTitle' "$today_log"
    assert_success
    run grep 'LogMessage' "$today_log"
    assert_success
    export HOME="$saved_home"
}

@test "log: adapter_send создаёт директорию при отсутствии" {
    local custom_log_dir="$BATS_TEST_TMPDIR/custom-logs/notify"
    source "$ADAPTERS/log.sh"
    # Переопределяем log_dir через env hack — адаптер использует $HOME
    local saved_home="$HOME"
    export HOME="$BATS_TEST_TMPDIR/custom-logs"

    run adapter_send "DirTest" "DirMsg"
    assert_success
    run test -d "$BATS_TEST_TMPDIR/custom-logs/.local/state/logs/notify"
    assert_success

    export HOME="$saved_home"
}

# ===========================================================================
# slack.sh
# ===========================================================================

@test "slack: adapter_enabled=false без SLACK_WEBHOOK_URL" {
    source "$ADAPTERS/slack.sh"
    unset SLACK_WEBHOOK_URL
    run adapter_enabled
    assert_failure
}

@test "slack: adapter_enabled=true с SLACK_WEBHOOK_URL" {
    source "$ADAPTERS/slack.sh"
    export SLACK_WEBHOOK_URL="https://hooks.slack.com/test"
    run adapter_enabled
    assert_success
}

@test "slack: adapter_min_level = notice" {
    source "$ADAPTERS/slack.sh"
    run adapter_min_level
    assert_success
    assert_output "notice"
}

# ===========================================================================
# email.sh
# ===========================================================================

@test "email: adapter_enabled=false без IWE_EMAIL_TO" {
    source "$ADAPTERS/email.sh"
    unset IWE_EMAIL_TO
    run adapter_enabled
    assert_failure
}

@test "email: adapter_enabled=true с IWE_EMAIL_TO" {
    source "$ADAPTERS/email.sh"
    export IWE_EMAIL_TO="user@example.com"
    run adapter_enabled
    assert_success
}

@test "email: adapter_min_level = critical" {
    source "$ADAPTERS/email.sh"
    run adapter_min_level
    assert_success
    assert_output "critical"
}

# ===========================================================================
# Дополнительные тесты (ADR-014 gaps)
# ===========================================================================

@test "slack: adapter_send возвращает 1 (stub)" {
    source "$ADAPTERS/slack.sh"
    run adapter_send "T" "M"
    assert_failure
    assert_output --partial "not implemented"
}

@test "email: adapter_send возвращает 1 (stub)" {
    source "$ADAPTERS/email.sh"
    run adapter_send "T" "M"
    assert_failure
    assert_output --partial "not implemented"
}

@test "telegram: HTML спецсимволы в title не ломают отправку" {
    cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do
  if [ "$1" = "-d" ]; then
    printf '%s' "$2" > "$BATS_TEST_TMPDIR/telegram_payload.json"
  fi
  shift
done
echo '{"ok":true}'
EOF
    chmod +x "$BIN_DIR/curl"
    source "$ADAPTERS/telegram.sh"
    export TELEGRAM_BOT_TOKEN="tok"
    export TELEGRAM_CHAT_ID="123"

    run adapter_send "Title <b>bold</b> & Entity" "Message"
    assert_success
    assert_output --partial "Sent via telegram"
    run python3 - "$BATS_TEST_TMPDIR/telegram_payload.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding='utf-8') as fh:
    data = json.load(fh)
assert data['parse_mode'] == 'HTML'
assert data['text'] == '<b>Title <b>bold</b> & Entity</b>\n\nMessage'
PY
    assert_success
}

@test "telegram: adapter_send с пустым message" {
    cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
echo '{"ok":true}'
EOF
    chmod +x "$BIN_DIR/curl"
    source "$ADAPTERS/telegram.sh"
    export TELEGRAM_BOT_TOKEN="tok"
    export TELEGRAM_CHAT_ID="123"

    run adapter_send "Title" ""
    assert_success
}

@test "log: % в title/message не ломает printf" {
    source "$ADAPTERS/log.sh"
    local saved_home="$HOME"
    export HOME="$BATS_TEST_TMPDIR/log-pct-test"
    run adapter_send "100% test %s" "%d items"
    assert_success
    # Проверяем что запись в log файле содержит оригинальный текст, не раскрытый printf
    local today_log="$HOME/.local/state/logs/notify/$(date +%Y-%m-%d).log"
    run grep '100% test %s' "$today_log"
    assert_success
    run grep '%d items' "$today_log"
    assert_success
    export HOME="$saved_home"
}
