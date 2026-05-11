#!/usr/bin/env bats
# End-to-end тесты: роль → notify_telegram → template → notify.sh → адаптеры
# ADR-014: Notification Observer Architecture

load '../../../tests/test_helper/bats-support/load'
load '../../../tests/test_helper/bats-assert/load'

setup() {
    TEST_DIR="$BATS_TEST_TMPDIR"
    BIN_DIR="$TEST_DIR/bin"
    mkdir -p "$BIN_DIR"
    export PATH="$BIN_DIR:$PATH"

    WORKSPACE_DIR="$TEST_DIR/workspace"
    mkdir -p "$WORKSPACE_DIR/DS-strategy/current" \
        "$WORKSPACE_DIR/DS-strategy/inbox/extraction-reports" \
        "$WORKSPACE_DIR/logs/synchronizer" \
        "$WORKSPACE_DIR/logs/extractor"
    export WORKSPACE_DIR

    LOG_FILE="$TEST_DIR/notify.log"

    NOTIFY_SH="${BATS_TEST_DIRNAME}/../../../scripts/notify.sh"
    ENV_FILE="$TEST_DIR/env"
    cat > "$ENV_FILE" <<EOF
TELEGRAM_BOT_TOKEN=int-token
TELEGRAM_CHAT_ID=99999
EOF
    export ENV_FILE
}

# ===========================================================================
# Стратег: notify_telegram + canary alert
# ===========================================================================

_make_dayplan() {
    local file="$WORKSPACE_DIR/DS-strategy/current/DayPlan $(date +%Y-%m-%d).md"
    printf '# Day Plan %s\n\n## План на сегодня\n| # | РП | Бюджет | Приоритет | Статус |\n|---|---|---|---|---|\n| 1 | Интеграционный тест | 2h | P1 | ✅ done |\n' "$(date +%Y-%m-%d)" > "$file"
    echo "$file"
}

@test "integration: стратег notify_telegram day-plan → notify.sh → telegram отправляет" {
    source "${BATS_TEST_DIRNAME}/../../../roles/shared/lib/lib-notify.sh"
    _make_dayplan

    cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
echo '{"ok":true}'
EOF
    chmod +x "$BIN_DIR/curl"

    local template="${BATS_TEST_DIRNAME}/../../strategist/scripts/templates/strategist.sh"
    export WORKSPACE_DIR IWE_NOTIFY_ENV_FILE="$ENV_FILE"
    local _msg
    _msg="$(bash -c 'source "$1"; build_message "$2"' _ "$template" "day-plan")" || true
    [[ -n "${_msg}" ]]

    run iwe_notify_via_script "$NOTIFY_SH" "Стратег: day-plan" "${_msg}" "notice" "$LOG_FILE"
    assert_success
}

@test "integration: стратег canary → notify.sh level=alert → отправляет" {
    source "${BATS_TEST_DIRNAME}/../../../roles/shared/lib/lib-notify.sh"

    cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
echo '{"ok":true}'
EOF
    chmod +x "$BIN_DIR/curl"

    export IWE_NOTIFY_ENV_FILE="$ENV_FILE"
    run iwe_notify_via_script "$NOTIFY_SH" \
        "Стратег: note-review-canary" \
        "⚠️ Canary: Step 10 не сработал (5 → 5 new bold)" \
        "alert" "$LOG_FILE"
    assert_success
}

# ===========================================================================
# Экстрактор: notify_telegram inbox-check
# ===========================================================================

@test "integration: экстрактор notify_telegram audit → notify.sh → log.sh пишет" {
    source "${BATS_TEST_DIRNAME}/../../../roles/shared/lib/lib-notify.sh"

    cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
echo '{"ok":true}'
EOF
    chmod +x "$BIN_DIR/curl"

    local template="${BATS_TEST_DIRNAME}/../../extractor/scripts/templates/extractor.sh"
    export WORKSPACE_DIR IWE_NOTIFY_ENV_FILE="$ENV_FILE"
    local _msg
    _msg="$(bash -c 'source "$1"; build_message "$2"' _ "$template" "audit")" || true
    [[ -n "${_msg}" ]]

    run iwe_notify_via_script "$NOTIFY_SH" "KE: audit" "${_msg}" "notice" "$LOG_FILE"
    assert_success
    run grep 'Sent via telegram' "$LOG_FILE"
    assert_success
}

# ===========================================================================
# Верификатор и Аудитор
# ===========================================================================

@test "integration: верификатор notify_telegram verify-content → notify.sh" {
    source "${BATS_TEST_DIRNAME}/../../../roles/shared/lib/lib-notify.sh"

    cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
echo '{"ok":true}'
EOF
    chmod +x "$BIN_DIR/curl"

    local template="${BATS_TEST_DIRNAME}/../../verifier/scripts/templates/verifier.sh"
    export WORKSPACE_DIR IWE_NOTIFY_ENV_FILE="$ENV_FILE"
    local _msg
    _msg="$(bash -c 'source "$1"; build_message "$2"' _ "$template" "verify-content")" || true
    [[ -n "${_msg}" ]]

    run iwe_notify_via_script "$NOTIFY_SH" "Верификатор: verify-content" "${_msg}" "notice" "$LOG_FILE"
    assert_success
    run grep 'Sent via telegram' "$LOG_FILE"
    assert_success
}

@test "integration: аудитор notify_telegram audit-coverage → notify.sh" {
    source "${BATS_TEST_DIRNAME}/../../../roles/shared/lib/lib-notify.sh"

    cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
echo '{"ok":true}'
EOF
    chmod +x "$BIN_DIR/curl"

    local template="${BATS_TEST_DIRNAME}/../../auditor/scripts/templates/auditor.sh"
    export WORKSPACE_DIR IWE_NOTIFY_ENV_FILE="$ENV_FILE"
    local _msg
    _msg="$(bash -c 'source "$1"; build_message "$2"' _ "$template" "audit-coverage")" || true
    [[ -n "${_msg}" ]]

    run iwe_notify_via_script "$NOTIFY_SH" "Аудитор: audit-coverage" "${_msg}" "notice" "$LOG_FILE"
    assert_success
    run grep 'Sent via telegram' "$LOG_FILE"
    assert_success
}

# ===========================================================================
# IWE_NOTIFY_ENV_FILE передаётся от роли к notify.sh
# ===========================================================================

@test "integration: IWE_NOTIFY_ENV_FILE передаётся всей цепочкой" {
    source "${BATS_TEST_DIRNAME}/../../../roles/shared/lib/lib-notify.sh"

    cat > "$BIN_DIR/curl" <<EOF
#!/usr/bin/env bash
echo "\$*" > "$TEST_DIR/curl_args"
echo '{"ok":true}'
EOF
    chmod +x "$BIN_DIR/curl"

    export WORKSPACE_DIR IWE_NOTIFY_ENV_FILE="$ENV_FILE"

    run iwe_notify_via_script "$NOTIFY_SH" "IntegrationTest" "Verify env file" "notice" "$LOG_FILE"
    assert_success

    run grep 'int-token' "$TEST_DIR/curl_args"
    assert_success
}

# ===========================================================================
# _sent >= 2 при telegram + log оба успешны
# ===========================================================================

@test "integration: telegram + log оба успешны — оба записаны" {
    cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
echo '{"ok":true}'
EOF
    chmod +x "$BIN_DIR/curl"

    local saved_home="$HOME"
    export HOME="$BATS_TEST_TMPDIR/log-integration-test"

    export IWE_NOTIFY_ENV_FILE="$ENV_FILE"
    run bash "$NOTIFY_SH" "BothAdapters" "TestMessage" notice
    assert_success
    assert_output --partial "Sent via telegram"

    # log.sh должен был записать
    local today_log="$HOME/.local/state/logs/notify/$(date +%Y-%m-%d).log"
    run grep 'BothAdapters' "$today_log"
    assert_success
    export HOME="$saved_home"
}
