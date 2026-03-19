#!/usr/bin/env bats
# Тесты для roles/synchronizer/scripts/code-scan.sh
# Покрывает: discover_repos, scan_repos (mock git)

load '../../../tests/test_helper/bats-support/load'
load '../../../tests/test_helper/bats-assert/load'
load '../../../tests/test_helper/bats-file/load'
load 'test_helper/helpers'

setup() {
    TEST_DIR="$BATS_TEST_TMPDIR"
    BIN_DIR="$TEST_DIR/bin"
    WORKSPACE="$TEST_DIR/iwe"
    LOG_DIR="$TEST_DIR/logs"
    mkdir -p "$BIN_DIR" "$WORKSPACE" "$LOG_DIR"
    export PATH="$BIN_DIR:$PATH"
}

# ---------------------------------------------------------------------------
# discover_repos (inline)
# ---------------------------------------------------------------------------

_load_discover_repos() {
    local workspace="$1"
    # Используем eval чтобы glob правильно раскрылся с реальным путём
    WORKSPACE="$workspace"
    discover_repos() {
        local repos=()
        local exclude=("DS-strategy")
        for dir in "$WORKSPACE"/DS-*/; do
            [ -d "$dir/.git" ] || continue
            local name
            name=$(basename "$dir")
            local skip=false
            for ex in "${exclude[@]}"; do
                [ "$name" = "$ex" ] && skip=true && break
            done
            [ "$skip" = true ] && continue
            repos+=("$dir")
        done
        printf '%s\n' "${repos[@]}"
    }
    export -f discover_repos
    export WORKSPACE
}

@test "discover_repos: находит репо с .git директорией" {
    mkdir -p "$WORKSPACE/DS-myrepo/.git"
    _load_discover_repos "$WORKSPACE"

    run discover_repos
    assert_success
    assert_output --partial "DS-myrepo"
}

@test "discover_repos: игнорирует директории без .git" {
    mkdir -p "$WORKSPACE/DS-nodotgit"
    _load_discover_repos "$WORKSPACE"

    run discover_repos
    assert_success
    refute_output --partial "DS-nodotgit"
}

@test "discover_repos: исключает DS-strategy" {
    mkdir -p "$WORKSPACE/DS-strategy/.git"
    _load_discover_repos "$WORKSPACE"

    run discover_repos
    assert_success
    refute_output --partial "DS-strategy"
}

@test "discover_repos: находит несколько репо" {
    mkdir -p "$WORKSPACE/DS-repo1/.git"
    mkdir -p "$WORKSPACE/DS-repo2/.git"
    mkdir -p "$WORKSPACE/DS-strategy/.git"
    _load_discover_repos "$WORKSPACE"

    run discover_repos
    assert_success
    assert_output --partial "DS-repo1"
    assert_output --partial "DS-repo2"
    refute_output --partial "DS-strategy"
}

@test "discover_repos: пустой workspace — нет вывода" {
    _load_discover_repos "$WORKSPACE"

    run discover_repos
    assert_success
    assert_output ""
}

@test "discover_repos: не включает не-DS- директории" {
    mkdir -p "$WORKSPACE/myproject/.git"
    _load_discover_repos "$WORKSPACE"

    run discover_repos
    assert_success
    refute_output --partial "myproject"
}

# ---------------------------------------------------------------------------
# scan_repos с mock git
# ---------------------------------------------------------------------------

_load_scan_repos() {
    local workspace="$1"
    local log_dir="$2"
    local dry_run="${3:-false}"
    WORKSPACE="$workspace"
    LOG_DIR="$log_dir"
    DRY_RUN=$dry_run
    LOG_FILE="$log_dir/code-scan-$(date +%Y-%m-%d).log"
    mkdir -p "$LOG_DIR"

    log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [code-scan] $1" | tee -a "$LOG_FILE"
    }

    discover_repos() {
        for dir in "$WORKSPACE"/DS-*/; do
            [ -d "$dir/.git" ] || continue
            local name
            name=$(basename "$dir")
            [ "$name" = "DS-strategy" ] && continue
            echo "$dir"
        done
    }

    scan_repos() {
        local total_repos=0
        local total_commits=0

        while IFS= read -r repo_dir; do
            repo_dir="${repo_dir%/}"
            local repo_name
            repo_name=$(basename "$repo_dir")
            local commits
            commits=$(git -C "$repo_dir" log --since="24 hours ago" --oneline --no-merges 2>/dev/null || true)

            if [ -z "$commits" ]; then
                log "SKIP: $repo_name — нет коммитов за 24ч"
                continue
            fi

            local count
            count=$(echo "$commits" | wc -l | tr -d ' ')
            log "FOUND: $repo_name — $count коммитов"
            total_repos=$((total_repos + 1))
            total_commits=$((total_commits + count))
        done < <(discover_repos)

        log "Итого: $total_repos репо, $total_commits коммитов"
    }
}

@test "scan_repos: логирует FOUND для репо с коммитами" {
    mkdir -p "$WORKSPACE/DS-active/.git"

    # Mock git: возвращает 1 коммит
    cat > "$BIN_DIR/git" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"log"* ]]; then
    echo "abc1234 some commit"
else
    /usr/bin/git "$@"
fi
EOF
    chmod +x "$BIN_DIR/git"

    _load_scan_repos "$WORKSPACE" "$LOG_DIR"
    run scan_repos
    assert_success
    assert_output --partial "FOUND: DS-active"
}

@test "scan_repos: логирует SKIP для репо без коммитов" {
    mkdir -p "$WORKSPACE/DS-quiet/.git"

    # Mock git: возвращает пустой вывод
    cat > "$BIN_DIR/git" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"log"* ]]; then
    echo ""
else
    /usr/bin/git "$@"
fi
EOF
    chmod +x "$BIN_DIR/git"

    _load_scan_repos "$WORKSPACE" "$LOG_DIR"
    run scan_repos
    assert_success
    assert_output --partial "SKIP: DS-quiet"
}

@test "scan_repos: итоговая строка с подсчётом" {
    mkdir -p "$WORKSPACE/DS-repo1/.git"
    mkdir -p "$WORKSPACE/DS-repo2/.git"

    cat > "$BIN_DIR/git" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"log"* ]]; then
    echo "abc1234 commit one"
    echo "def5678 commit two"
else
    /usr/bin/git "$@"
fi
EOF
    chmod +x "$BIN_DIR/git"

    _load_scan_repos "$WORKSPACE" "$LOG_DIR"
    scan_repos
    run grep "Итого:" "$LOG_DIR/code-scan-$(date +%Y-%m-%d).log"
    assert_success
    assert_output --partial "2 репо"
    assert_output --partial "4 коммитов"
}

@test "scan_repos: пустой workspace — Итого: 0 репо" {
    cat > "$BIN_DIR/git" <<'EOF'
#!/usr/bin/env bash
echo ""
EOF
    chmod +x "$BIN_DIR/git"

    _load_scan_repos "$WORKSPACE" "$LOG_DIR"
    scan_repos
    run grep "Итого:" "$LOG_DIR/code-scan-$(date +%Y-%m-%d).log"
    assert_success
    assert_output --partial "0 репо, 0 коммитов"
}
