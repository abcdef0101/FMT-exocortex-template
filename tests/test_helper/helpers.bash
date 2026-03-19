# Общие хелперы для тестов setup.sh

SETUP_SCRIPT="${BATS_TEST_DIRNAME}/../setup.sh"

# Создать минимальную структуру template (CLAUDE.md + memory/)
make_template_dir() {
    local dir="$1"
    mkdir -p "$dir/memory" "$dir/.githooks"
    touch "$dir/CLAUDE.md"
    touch "$dir/memory/MEMORY.md"
    touch "$dir/CHANGELOG.md"
    # Создаём тестовые файлы с плейсхолдерами
    cat > "$dir/memory/test.md" <<'EOF'
# Test
workspace: {{WORKSPACE_DIR}}
user: {{GITHUB_USER}}
repo: {{EXOCORTEX_REPO}}
claude: {{CLAUDE_PATH}}
home: {{HOME_DIR}}
slug: {{CLAUDE_PROJECT_SLUG}}
tz_hour: {{TIMEZONE_HOUR}}
tz_desc: {{TIMEZONE_DESC}}
EOF
    cat > "$dir/test.yaml" <<'EOF'
workspace: {{WORKSPACE_DIR}}
repo: {{EXOCORTEX_REPO}}
EOF
}

# Запустить setup.sh в dry-run с предустановленными переменными (без интерактива)
run_setup_dry() {
    local template_dir="$1"
    shift
    local extra_args=("$@")

    # Подаём ответы на read-вопросы через stdin
    run bash "$SETUP_SCRIPT" --dry-run "${extra_args[@]}" <<'INPUT'
testuser
DS-myexo
/tmp/test-workspace
/usr/local/bin/claude
4
4:00 UTC
INPUT
}

# Мокируем внешние команды через PATH
setup_mocks() {
    local bin_dir="$1"
    mkdir -p "$bin_dir"

    # git mock
    cat > "$bin_dir/git" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    config) exit 0 ;;
    *)      /usr/bin/git "$@" ;;
esac
EOF
    chmod +x "$bin_dir/git"

    # gh mock (не авторизован по умолчанию)
    cat > "$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    auth) exit 0 ;;
    repo) exit 0 ;;
    *)    exit 0 ;;
esac
EOF
    chmod +x "$bin_dir/gh"

    # claude mock
    cat > "$bin_dir/claude" <<'EOF'
#!/usr/bin/env bash
echo "mock claude $*"
exit 0
EOF
    chmod +x "$bin_dir/claude"

    export PATH="$bin_dir:$PATH"
}
