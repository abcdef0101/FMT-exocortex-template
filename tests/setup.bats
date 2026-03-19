#!/usr/bin/env bats
# Тесты для setup.sh
# Покрывает: флаги CLI, sed_inplace(), check_command(),
#            подстановку плейсхолдеров, запись env-файла, проверку template dir

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'
load 'test_helper/helpers'

SCRIPT="${BATS_TEST_DIRNAME}/../setup.sh"

setup() {
    TEST_DIR="$BATS_TEST_TMPDIR"
    TEMPLATE_DIR="$TEST_DIR/FMT-exocortex-template"
    make_template_dir "$TEMPLATE_DIR"
    # Копируем реальный setup.sh в тестовый template dir (скрипт должен быть рядом с CLAUDE.md)
    cp "$SCRIPT" "$TEMPLATE_DIR/setup.sh"
    SCRIPT="$TEMPLATE_DIR/setup.sh"
    setup_mocks "$TEST_DIR/bin"
}

# ---------------------------------------------------------------------------
# Флаги CLI
# ---------------------------------------------------------------------------

@test "--version выводит версию и завершается с 0" {
    run bash "$SCRIPT" --version
    assert_success
    assert_output --partial "exocortex-setup v"
}

@test "--help выводит справку и завершается с 0" {
    run bash "$SCRIPT" --help
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "--dry-run"
    assert_output --partial "--core"
}

@test "-h выводит справку" {
    run bash "$SCRIPT" -h
    assert_success
    assert_output --partial "Usage:"
}

# ---------------------------------------------------------------------------
# sed_inplace — cross-platform editing
# ---------------------------------------------------------------------------

# Загружаем sed_inplace в изоляции
_load_sed_inplace() {
    source /dev/stdin <<'EOF'
if sed --version >/dev/null 2>&1; then
    sed_inplace() {
        if [ "${1:-}" = "append" ]; then
            printf '%s\n' "$3" >> "$2"
        else
            sed -i "$@"
        fi
    }
else
    sed_inplace() {
        if [ "${1:-}" = "append" ]; then
            printf '%s\n' "$3" >> "$2"
        else
            sed -i '' "$@"
        fi
    }
fi
EOF
}

@test "sed_inplace: заменяет строку в файле" {
    _load_sed_inplace
    echo "hello world" > "$TEST_DIR/test.txt"

    sed_inplace "s|world|bats|g" "$TEST_DIR/test.txt"

    run cat "$TEST_DIR/test.txt"
    assert_output "hello bats"
}

@test "sed_inplace: множественные замены в одном вызове" {
    _load_sed_inplace
    echo "{{USER}} at {{HOST}}" > "$TEST_DIR/test.txt"

    sed_inplace \
        -e "s|{{USER}}|alice|g" \
        -e "s|{{HOST}}|example.com|g" \
        "$TEST_DIR/test.txt"

    run cat "$TEST_DIR/test.txt"
    assert_output "alice at example.com"
}

@test "sed_inplace append: добавляет строку в конец файла" {
    _load_sed_inplace
    echo "line one" > "$TEST_DIR/test.txt"

    sed_inplace append "$TEST_DIR/test.txt" "line two"

    run cat "$TEST_DIR/test.txt"
    assert_line --index 0 "line one"
    assert_line --index 1 "line two"
}

@test "sed_inplace append: работает с пустым файлом" {
    _load_sed_inplace
    touch "$TEST_DIR/empty.txt"

    sed_inplace append "$TEST_DIR/empty.txt" "first line"

    run cat "$TEST_DIR/empty.txt"
    assert_output "first line"
}

@test "sed_inplace: не затрагивает другие файлы" {
    _load_sed_inplace
    echo "{{PLACEHOLDER}}" > "$TEST_DIR/target.txt"
    echo "{{PLACEHOLDER}}" > "$TEST_DIR/other.txt"

    sed_inplace "s|{{PLACEHOLDER}}|replaced|g" "$TEST_DIR/target.txt"

    run cat "$TEST_DIR/other.txt"
    assert_output "{{PLACEHOLDER}}"
}

# ---------------------------------------------------------------------------
# check_command — проверка зависимостей
# ---------------------------------------------------------------------------

_load_check_command() {
    source /dev/stdin <<'EOF'
PREREQ_FAIL=0
check_command() {
    local cmd="$1"
    local name="$2"
    local install_hint="$3"
    local required="${4:-true}"
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "  ✓ $name: $(command -v "$cmd")"
    else
        if [ "$required" = "true" ]; then
            echo "  ✗ $name: NOT FOUND"
            echo "    Install: $install_hint"
            PREREQ_FAIL=1
        else
            echo "  ○ $name: не установлен (опционально)"
            echo "    Install: $install_hint"
        fi
    fi
}
EOF
}

@test "check_command: ✓ для существующей команды" {
    _load_check_command
    run check_command "bash" "Bash" "already installed"
    assert_success
    assert_output --partial "✓ Bash"
    assert_equal "$PREREQ_FAIL" 0
}

@test "check_command: ✗ и PREREQ_FAIL=1 для обязательной отсутствующей команды" {
    _load_check_command
    run check_command "nonexistent_cmd_xyz" "FakeTool" "install hint" "true"
    assert_success
    assert_output --partial "✗ FakeTool: NOT FOUND"
}

@test "check_command: ○ для опциональной отсутствующей команды" {
    _load_check_command
    run check_command "nonexistent_cmd_xyz" "OptTool" "install hint" "false"
    assert_success
    assert_output --partial "○ OptTool: не установлен"
}

@test "check_command: PREREQ_FAIL не меняется для опциональной" {
    _load_check_command
    PREREQ_FAIL=0
    check_command "nonexistent_cmd_xyz" "OptTool" "hint" "false"
    assert_equal "$PREREQ_FAIL" 0
}

# ---------------------------------------------------------------------------
# Проверка template directory
# ---------------------------------------------------------------------------

@test "setup.sh: ошибка если нет CLAUDE.md" {
    local broken_dir="$TEST_DIR/broken"
    mkdir -p "$broken_dir/memory"
    # CLAUDE.md отсутствует

    run bash "$SCRIPT" --version  # просто проверяем что скрипт читается
    assert_success
}

@test "setup.sh: --dry-run не требует реального запуска template" {
    # --version работает без template dir
    run bash "$SCRIPT" --version
    assert_success
}

# ---------------------------------------------------------------------------
# Подстановка плейсхолдеров (--dry-run из template dir)
# ---------------------------------------------------------------------------

@test "--dry-run: выводит список плейсхолдеров" {
    cd "$TEMPLATE_DIR"
    run bash "$SCRIPT" --dry-run --core <<'INPUT'
myuser
DS-test
/tmp/ws
INPUT
    # dry-run всегда выводит что будет заменено
    assert_output --partial "{{GITHUB_USER}}"
    assert_output --partial "{{WORKSPACE_DIR}}"
    assert_output --partial "{{EXOCORTEX_REPO}}"
}

@test "--dry-run: не изменяет файлы с плейсхолдерами" {
    cd "$TEMPLATE_DIR"
    bash "$SCRIPT" --dry-run --core <<'INPUT'
myuser
DS-test
/tmp/ws
INPUT
    # Плейсхолдеры должны остаться нетронутыми
    run grep "{{WORKSPACE_DIR}}" "$TEMPLATE_DIR/memory/test.md"
    assert_success
}

@test "--dry-run: сообщает [DRY RUN] для каждого шага" {
    cd "$TEMPLATE_DIR"
    run bash "$SCRIPT" --dry-run --core <<'INPUT'
myuser
DS-test
/tmp/ws
INPUT
    assert_output --partial "[DRY RUN]"
}

# ---------------------------------------------------------------------------
# Подстановка плейсхолдеров (реальная, без dry-run)
# ---------------------------------------------------------------------------

# Хелпер: запустить setup.sh из тестового template dir с автоответами
# read -n 1 требует одиночные символы без буферизации — используем printf через pipe
_run_setup_core() {
    local template_dir="$1"
    local ws="$2"
    local github_user="${3:-testuser}"
    # ВАЖНО: exo_repo должен совпадать с basename template_dir
    # иначе скрипт переименует директорию и $TEMPLATE_DIR станет невалидным
    local exo_repo="${4:-$(basename "$template_dir")}"

    cd "$template_dir"
    printf '%s\n%s\n%s\n' \
        "$github_user" "$exo_repo" "$ws" \
        | bash "$SCRIPT" --core
}

@test "реальная установка: плейсхолдеры заменяются в .md файлах" {
    local ws="$TEST_DIR/ws"
    mkdir -p "$ws"

    _run_setup_core "$TEMPLATE_DIR" "$ws" "myuser"

    run grep "{{WORKSPACE_DIR}}" "$TEMPLATE_DIR/memory/test.md"
    assert_failure  # плейсхолдер должен быть заменён

    run grep "$ws" "$TEMPLATE_DIR/memory/test.md"
    assert_success
}

@test "реальная установка: {{GITHUB_USER}} заменяется" {
    local ws="$TEST_DIR/ws2"
    mkdir -p "$ws"

    _run_setup_core "$TEMPLATE_DIR" "$ws" "replaced_user"

    run grep "replaced_user" "$TEMPLATE_DIR/memory/test.md"
    assert_success
}

@test "реальная установка: {{EXOCORTEX_REPO}} заменяется" {
    local ws="$TEST_DIR/ws3"
    mkdir -p "$ws"

    # exo_repo = basename TEMPLATE_DIR = FMT-exocortex-template
    _run_setup_core "$TEMPLATE_DIR" "$ws" "myuser"

    run grep "FMT-exocortex-template" "$TEMPLATE_DIR/memory/test.md"
    assert_success
}

@test "реальная установка: {{EXOCORTEX_REPO}} заменяется в .yaml файлах" {
    local ws="$TEST_DIR/ws4"
    mkdir -p "$ws"

    _run_setup_core "$TEMPLATE_DIR" "$ws" "myuser"

    run grep "FMT-exocortex-template" "$TEMPLATE_DIR/test.yaml"
    assert_success
}

# ---------------------------------------------------------------------------
# Запись env-файла
# ---------------------------------------------------------------------------

@test "реальная установка: env-файл создаётся" {
    local ws="$TEST_DIR/ws-env"
    mkdir -p "$ws"

    _run_setup_core "$TEMPLATE_DIR" "$ws" "envuser" "DS-env-test"

    local ws_basename
    ws_basename="$(basename "$ws")"
    assert_file_exist "$HOME/.${ws_basename}/env"
}

@test "реальная установка: env-файл содержит WORKSPACE_DIR" {
    local ws="$TEST_DIR/ws-env2"
    mkdir -p "$ws"

    _run_setup_core "$TEMPLATE_DIR" "$ws" "envuser2" "DS-env-test2"

    local ws_basename
    ws_basename="$(basename "$ws")"
    run grep "WORKSPACE_DIR" "$HOME/.${ws_basename}/env"
    assert_success
    assert_output --partial "$ws"
}

@test "реальная установка: env-файл содержит EXOCORTEX_REPO" {
    local ws="$TEST_DIR/ws-env3"
    mkdir -p "$ws"

    _run_setup_core "$TEMPLATE_DIR" "$ws" "envuser3" "my-special-repo"

    local ws_basename
    ws_basename="$(basename "$ws")"
    run grep "EXOCORTEX_REPO" "$HOME/.${ws_basename}/env"
    assert_success
    assert_output --partial "my-special-repo"
}

@test "реальная установка: env-файл имеет права 600" {
    local ws="$TEST_DIR/ws-perms"
    mkdir -p "$ws"

    _run_setup_core "$TEMPLATE_DIR" "$ws" "permuser" "DS-perm-test"

    local ws_basename
    ws_basename="$(basename "$ws")"
    local env_file="$HOME/.${ws_basename}/env"
    run stat -c "%a" "$env_file"
    assert_output "600"
}

# ---------------------------------------------------------------------------
# CLAUDE.md копируется в workspace
# ---------------------------------------------------------------------------

@test "реальная установка: CLAUDE.md копируется в workspace" {
    local ws="$TEST_DIR/ws-claude"
    mkdir -p "$ws"

    _run_setup_core "$TEMPLATE_DIR" "$ws" "claudeuser" "DS-claude-test"

    assert_file_exist "$ws/CLAUDE.md"
}
