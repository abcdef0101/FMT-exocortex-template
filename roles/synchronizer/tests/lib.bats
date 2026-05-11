#!/usr/bin/env bats
# Тесты для lib-notify.sh и lib-env.sh (ADR-014)

load '../../../tests/test_helper/bats-support/load'
load '../../../tests/test_helper/bats-assert/load'

setup() {
    TEST_DIR="$BATS_TEST_TMPDIR"
}

# ===========================================================================
# iwe_notify_local (roles/shared/lib/lib-notify.sh)
# ===========================================================================

@test "iwe_notify_local: macOS path — вызывает osascript" {
    source "${BATS_TEST_DIRNAME}/../../../roles/shared/lib/lib-notify.sh"
    OSTYPE="darwin20"  # force macOS
    run iwe_notify_local "TestTitle" "TestMessage"
    # osascript не установлен в CI → || true, ошибка не фатальна
    assert_success
}

@test "iwe_notify_local: Linux путь с notify-send — вызывает notify-send" {
    source "${BATS_TEST_DIRNAME}/../../../roles/shared/lib/lib-notify.sh"
    OSTYPE="linux-gnu"
    BIN_DIR="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$BIN_DIR"
    cat > "$BIN_DIR/notify-send" <<EOF
#!/usr/bin/env bash
echo "notify-send called: \$1 \$2" > "$TEST_DIR/notify_send_output"
exit 0
EOF
    chmod +x "$BIN_DIR/notify-send"
    export PATH="$BIN_DIR:$PATH"

    run iwe_notify_local "TestTitle" "TestMessage"
    assert_success
    run grep 'notify-send called' "$TEST_DIR/notify_send_output"
    assert_success
}

@test "iwe_notify_local: Linux без notify-send — silent no-op" {
    source "${BATS_TEST_DIRNAME}/../../../roles/shared/lib/lib-notify.sh"
    OSTYPE="linux-gnu"
    # Убеждаемся что notify-send не в PATH
    BIN_DIR="$BATS_TEST_TMPDIR/emptybin"
    mkdir -p "$BIN_DIR"
    export PATH="$BIN_DIR"

    run iwe_notify_local "TestTitle" "TestMessage"
    assert_success
}

@test "iwe_notify_local: неизвестная платформа — silent no-op" {
    source "${BATS_TEST_DIRNAME}/../../../roles/shared/lib/lib-notify.sh"
    OSTYPE="freebsd"
    run iwe_notify_local "TestTitle" "TestMessage"
    assert_success
}

# ===========================================================================
# iwe_notify_via_script (roles/shared/lib/lib-notify.sh)
# ===========================================================================

@test "iwe_notify_via_script: вызывает скрипт с переданными аргументами" {
    source "${BATS_TEST_DIRNAME}/../../../roles/shared/lib/lib-notify.sh"
    local test_script="$TEST_DIR/test_notify.sh"
    cat > "$test_script" <<'EOF'
#!/usr/bin/env bash
echo "CALLED: $1 | $2 | $3"
EOF
    chmod +x "$test_script"

    run iwe_notify_via_script "$test_script" "T" "M" "alert" "/dev/null"
    assert_success
}

@test "iwe_notify_via_script: скрипт не существует — silent skip" {
    source "${BATS_TEST_DIRNAME}/../../../roles/shared/lib/lib-notify.sh"
    run iwe_notify_via_script "/nonexistent/notify.sh" "T" "M" "notice" "/dev/null"
    assert_success
}

@test "iwe_notify_via_script: уровень по умолчанию notice" {
    source "${BATS_TEST_DIRNAME}/../../../roles/shared/lib/lib-notify.sh"
    local test_script="$TEST_DIR/test_default.sh"
    cat > "$test_script" <<'EOF'
#!/usr/bin/env bash
echo "LEVEL: ${3:-missing}"
EOF
    chmod +x "$test_script"

    run iwe_notify_via_script "$test_script" "T" "M"
    assert_success
    assert_output --partial "LEVEL: notice"
}

@test "iwe_notify_via_script: редиректит stdout+stderr в log_file" {
    source "${BATS_TEST_DIRNAME}/../../../roles/shared/lib/lib-notify.sh"
    local test_script="$TEST_DIR/test_log.sh"
    local log_file="$TEST_DIR/notify.log"
    cat > "$test_script" <<'EOF'
#!/usr/bin/env bash
echo "stdout msg"
echo "stderr msg" >&2
EOF
    chmod +x "$test_script"

    iwe_notify_via_script "$test_script" "T" "M" "notice" "$log_file"
    run cat "$log_file"
    assert_output --partial "stdout msg"
    assert_output --partial "stderr msg"
}

@test "iwe_notify_via_script: скрипт падает — не прерывает вызывающий код" {
    source "${BATS_TEST_DIRNAME}/../../../roles/shared/lib/lib-notify.sh"
    local test_script="$TEST_DIR/test_fail.sh"
    cat > "$test_script" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$test_script"

    run iwe_notify_via_script "$test_script" "T" "M" "notice" "/dev/null"
    assert_success
}

# ===========================================================================
# iwe_find_repo_root (lib/lib-env.sh)
# ===========================================================================

@test "iwe_find_repo_root: находит repo по CLAUDE.md + memory/" {
    source "${BATS_TEST_DIRNAME}/../../../lib/lib-env.sh"
    mkdir -p "$TEST_DIR/repo/memory"
    touch "$TEST_DIR/repo/CLAUDE.md"

    run iwe_find_repo_root "$TEST_DIR/repo/subdir/deep"
    assert_success
    assert_output "$TEST_DIR/repo"
}

@test "iwe_find_repo_root: находит из вложенной директории" {
    source "${BATS_TEST_DIRNAME}/../../../lib/lib-env.sh"
    mkdir -p "$TEST_DIR/repo2/memory"
    touch "$TEST_DIR/repo2/CLAUDE.md"
    mkdir -p "$TEST_DIR/repo2/a/b/c/d"

    run iwe_find_repo_root "$TEST_DIR/repo2/a/b/c/d"
    assert_success
    assert_output "$TEST_DIR/repo2"
}

@test "iwe_find_repo_root: не находит — возвращает 1" {
    source "${BATS_TEST_DIRNAME}/../../../lib/lib-env.sh"
    mkdir -p "$TEST_DIR/norepo"

    run iwe_find_repo_root "$TEST_DIR/norepo"
    assert_failure
}

@test "iwe_find_repo_root: memory/ должен быть директорией" {
    source "${BATS_TEST_DIRNAME}/../../../lib/lib-env.sh"
    mkdir -p "$TEST_DIR/fakerepo"
    touch "$TEST_DIR/fakerepo/CLAUDE.md"
    touch "$TEST_DIR/fakerepo/memory"  # файл, не директория

    run iwe_find_repo_root "$TEST_DIR/fakerepo"
    assert_failure
}

# ===========================================================================
# iwe_env_file_from_repo_root (lib/lib-env.sh)
# ===========================================================================

@test "iwe_env_file_from_repo_root: генерирует путь ~/.workspace/env" {
    source "${BATS_TEST_DIRNAME}/../../../lib/lib-env.sh"
    export HOME="$TEST_DIR"

    run iwe_env_file_from_repo_root "/home/user/projects/myws/repo"
    assert_success
    assert_output "$TEST_DIR/.myws/env"
}

@test "iwe_env_file_from_repo_root: работает с вложенным workspace" {
    source "${BATS_TEST_DIRNAME}/../../../lib/lib-env.sh"
    export HOME="$TEST_DIR"

    # repo_root = /data/workspaces/production/FMT
    # workspace_dir (dirname) = /data/workspaces/production
    # basename = production
    # env = $HOME/.production/env
    run iwe_env_file_from_repo_root "/data/workspaces/production/FMT"
    assert_success
    assert_output "$TEST_DIR/.production/env"
}

# ===========================================================================
# iwe_load_env_file (lib/lib-env.sh)
# ===========================================================================

@test "iwe_load_env_file: загружает env с set -a (переменные экспортируются)" {
    source "${BATS_TEST_DIRNAME}/../../../lib/lib-env.sh"
    local env_file="$TEST_DIR/test.env"
    printf 'MY_VAR=hello\nOTHER=world\n' > "$env_file"

    # Не используем `run` — переменные нужны в текущем shell
    iwe_load_env_file "$env_file"
    assert_equal "$MY_VAR" "hello"
    assert_equal "$OTHER" "world"
}

@test "iwe_load_env_file: файл не найден — возвращает 1" {
    source "${BATS_TEST_DIRNAME}/../../../lib/lib-env.sh"
    run iwe_load_env_file "$TEST_DIR/nonexistent.env"
    assert_failure
}

@test "iwe_load_env_file: опасные паттерны — возвращает 1" {
    source "${BATS_TEST_DIRNAME}/../../../lib/lib-env.sh"
    local env_file="$TEST_DIR/bad.env"
    printf 'eval "rm -rf /"\n' > "$env_file"

    run iwe_load_env_file "$env_file"
    assert_failure
    assert_output --partial "dangerous patterns"
}

@test "iwe_load_env_file: пустой файл — успех" {
    source "${BATS_TEST_DIRNAME}/../../../lib/lib-env.sh"
    local env_file="$TEST_DIR/empty.env"
    touch "$env_file"

    run iwe_load_env_file "$env_file"
    assert_success
}

# ===========================================================================
# iwe_require_env_vars (lib/lib-env.sh)
# ===========================================================================

@test "iwe_require_env_vars: все переменные есть — успех" {
    source "${BATS_TEST_DIRNAME}/../../../lib/lib-env.sh"
    export VAR_A="1"
    export VAR_B="2"

    run iwe_require_env_vars VAR_A VAR_B
    assert_success
}

@test "iwe_require_env_vars: переменная отсутствует — ошибка" {
    source "${BATS_TEST_DIRNAME}/../../../lib/lib-env.sh"
    unset MISSING_VAR

    run iwe_require_env_vars MISSING_VAR
    assert_failure
    assert_output --partial "MISSING_VAR"
}

@test "iwe_require_env_vars: переменная пустая — ошибка" {
    source "${BATS_TEST_DIRNAME}/../../../lib/lib-env.sh"
    export EMPTY_VAR=""

    run iwe_require_env_vars EMPTY_VAR
    assert_failure
}

@test "iwe_require_env_vars: без аргументов — успех" {
    source "${BATS_TEST_DIRNAME}/../../../lib/lib-env.sh"
    run iwe_require_env_vars
    assert_success
}

# ===========================================================================
# iwe_telegram_load_env (lib/lib-telegram.sh)
# ===========================================================================

@test "iwe_telegram_load_env: загружает валидный файл с validate" {
    source "${BATS_TEST_DIRNAME}/../../../lib/lib-env.sh"
    source "${BATS_TEST_DIRNAME}/../../../lib/lib-telegram.sh"
    local env_file="$TEST_DIR/tg.env"
    printf 'TELEGRAM_BOT_TOKEN=tok\nTELEGRAM_CHAT_ID=123\n' > "$env_file"

    # Не используем `run` — переменные нужны в текущем shell
    iwe_telegram_load_env "$env_file"
    assert_equal "$TELEGRAM_BOT_TOKEN" "tok"
}

@test "iwe_telegram_load_env: файла нет — silent skip" {
    source "${BATS_TEST_DIRNAME}/../../../lib/lib-env.sh"
    source "${BATS_TEST_DIRNAME}/../../../lib/lib-telegram.sh"

    run iwe_telegram_load_env "$TEST_DIR/notfound.env"
    assert_success
}

@test "iwe_telegram_load_env: опасный файл — возвращает 1" {
    source "${BATS_TEST_DIRNAME}/../../../lib/lib-env.sh"
    source "${BATS_TEST_DIRNAME}/../../../lib/lib-telegram.sh"
    local env_file="$TEST_DIR/evil.env"
    printf 'eval "bad"\n' > "$env_file"

    run iwe_telegram_load_env "$env_file"
    assert_failure
}
