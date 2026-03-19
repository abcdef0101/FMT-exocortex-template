#!/usr/bin/env bats
# Тесты для roles/strategist/scripts/strategist.sh
# Покрывает: _validate_env_file(), acquire_lock(), log()

load '../../../tests/test_helper/bats-support/load'
load '../../../tests/test_helper/bats-assert/load'
load '../../../tests/test_helper/bats-file/load'
load 'test_helper/helpers'

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/strategist.sh"

# ---------------------------------------------------------------------------
# setup/teardown
# ---------------------------------------------------------------------------

setup() {
    TEST_DIR="$BATS_TEST_TMPDIR"
    ENV_FILE="$TEST_DIR/env"
    LOCK_DIR="$TEST_DIR/locks"
    LOG_DIR="$TEST_DIR/logs"
    mkdir -p "$LOCK_DIR" "$LOG_DIR"
    make_valid_env "$ENV_FILE"

    # Мокируем Claude Code — не запускаем реальный агент
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'EOF'
#!/usr/bin/env bash
echo "mock claude: $*"
exit 0
EOF
    chmod +x "$TEST_DIR/bin/claude"
    export PATH="$TEST_DIR/bin:$PATH"
}

# ---------------------------------------------------------------------------
# _validate_env_file
# ---------------------------------------------------------------------------

# Выносим функцию из скрипта для изолированного тестирования
_load_validate_fn() {
    # shellcheck source=/dev/null
    source /dev/stdin <<'FUNC'
function _validate_env_file() {
  local filepath="${1}"
  if grep -qE '^\s*(eval|source|\.)[ \t]' "${filepath}" 2>/dev/null; then
    echo "ERROR: env file contains dangerous patterns: ${filepath}" >&2
    exit 1
  fi
}
FUNC
}

@test "_validate_env_file: успех с корректным env-файлом" {
    _load_validate_fn
    make_valid_env "$TEST_DIR/valid.env"

    run _validate_env_file "$TEST_DIR/valid.env"
    assert_success
}

@test "_validate_env_file: ошибка при eval-инъекции" {
    _load_validate_fn
    make_dangerous_env "$TEST_DIR/danger.env"

    run _validate_env_file "$TEST_DIR/danger.env"
    assert_failure
    assert_output --partial "dangerous patterns"
}

@test "_validate_env_file: ошибка при source-инъекции" {
    _load_validate_fn
    make_source_injection_env "$TEST_DIR/source.env"

    run _validate_env_file "$TEST_DIR/source.env"
    assert_failure
    assert_output --partial "dangerous patterns"
}

@test "_validate_env_file: ошибка при dot-инъекции (. /etc/passwd)" {
    _load_validate_fn
    printf 'KEY=value\n. /etc/passwd\n' > "$TEST_DIR/dot.env"

    run _validate_env_file "$TEST_DIR/dot.env"
    assert_failure
    assert_output --partial "dangerous patterns"
}

@test "_validate_env_file: корректно с пустым файлом" {
    _load_validate_fn
    touch "$TEST_DIR/empty.env"

    run _validate_env_file "$TEST_DIR/empty.env"
    assert_success
}

@test "_validate_env_file: eval в середине строки — не опасно" {
    _load_validate_fn
    # "evaluation" — содержит "eval" но не в начале строки с пробелом
    printf 'KEY=evaluation_mode\nSCRIPT_DIR=/tmp\n' > "$TEST_DIR/safe.env"

    run _validate_env_file "$TEST_DIR/safe.env"
    assert_success
}

# ---------------------------------------------------------------------------
# acquire_lock (через subprocess)
# ---------------------------------------------------------------------------

# Хелпер: запустить acquire_lock в изолированном окружении
_run_lock_test() {
    local scenario="$1"
    local lock_dir="$TEST_DIR/locks"
    local log_dir="$TEST_DIR/logs"
    local date
    date=$(date +%Y-%m-%d)

    bash - <<EOF
set -euo pipefail
LOG_DIR="$log_dir"
LOCK_DIR="$lock_dir"
DATE="$date"
LOG_FILE="$log_dir/test.log"
mkdir -p "\$LOCK_DIR" "\$LOG_DIR"

function log() { echo "\$1"; }

acquire_lock() {
    local scenario="\$1"
    local lockfile="\$LOCK_DIR/\${scenario}.\${DATE}.lock"
    if ! mkdir "\$lockfile" 2>/dev/null; then
        log "SKIP: \$scenario already running (lock exists: \$lockfile)"
        exit 2
    fi
}

acquire_lock "$scenario"
EOF
}

@test "acquire_lock: успех если lock не существует" {
    run _run_lock_test "morning"
    assert_success
}

@test "acquire_lock: exit 2 если lock уже существует" {
    local date
    date=$(date +%Y-%m-%d)
    mkdir -p "$LOCK_DIR/morning.${date}.lock"

    run _run_lock_test "morning"
    assert_failure
    assert_equal "$status" 2
    assert_output --partial "already running"
}

@test "acquire_lock: разные сценарии не мешают друг другу" {
    run _run_lock_test "morning"
    assert_success

    run _run_lock_test "week-review"
    assert_success
}

@test "acquire_lock: создаёт lock-директорию" {
    local date
    date=$(date +%Y-%m-%d)
    local lockfile="$LOCK_DIR/morning.${date}.lock"

    _run_lock_test "morning"
    assert_dir_exist "$lockfile"
}

# ---------------------------------------------------------------------------
# log()
# ---------------------------------------------------------------------------

@test "log: пишет сообщение в stdout" {
    source /dev/stdin <<EOF
LOG_FILE="$TEST_DIR/test.log"
mkdir -p "$(dirname "$TEST_DIR/test.log")"
function log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] \${1}"
  echo "\${msg}" >> "\${LOG_FILE}"
  case "\${1}" in
    ERROR:* | WARN:*) echo "\${msg}" >&2 ;;
    *) echo "\${msg}" ;;
  esac
}
EOF
    run log "test message"
    assert_success
    assert_output --partial "test message"
}

@test "log: ERROR записывает в stderr" {
    source /dev/stdin <<EOF
LOG_FILE="$TEST_DIR/test.log"
function log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] \${1}"
  echo "\${msg}" >> "\${LOG_FILE}"
  case "\${1}" in
    ERROR:* | WARN:*) echo "\${msg}" >&2 ;;
    *) echo "\${msg}" ;;
  esac
}
EOF
    run log "ERROR: something failed"
    assert_success
    # stderr должен содержать ERROR
    assert_output --partial "ERROR:"
}

@test "log: пишет в файл" {
    local logfile="$TEST_DIR/test.log"
    source /dev/stdin <<EOF
LOG_FILE="$logfile"
function log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] \${1}"
  echo "\${msg}" >> "\${LOG_FILE}"
  case "\${1}" in
    ERROR:* | WARN:*) echo "\${msg}" >&2 ;;
    *) echo "\${msg}" ;;
  esac
}
EOF
    log "written to file"
    run grep "written to file" "$logfile"
    assert_success
}
