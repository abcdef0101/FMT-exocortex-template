#!/usr/bin/env bats

load '../../../tests/test_helper/bats-support/load'
load '../../../tests/test_helper/bats-assert/load'
load '../../../tests/test_helper/bats-file/load'
load 'test_helper/helpers'

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/extractor.sh"
SCRIPTS_DIR="${BATS_TEST_DIRNAME}/../scripts"
PROMPTS_DIR="${BATS_TEST_DIRNAME}/../prompts"

setup() {
  TEST_DIR="$BATS_TEST_TMPDIR"
  HOME_DIR="$TEST_DIR/home"
  WORKSPACE_DIR="$TEST_DIR/workspace"
  BIN_DIR="$TEST_DIR/bin"
  MOCK_CLAUDE_ARGS_FILE="$TEST_DIR/claude-args.txt"
  MOCK_GIT_ARGS_FILE="$TEST_DIR/git-args.txt"
  MOCK_NOTIFY_FILE="$TEST_DIR/notify.txt"
  mkdir -p "$HOME_DIR" "$WORKSPACE_DIR/DS-strategy/inbox/extraction-reports" "$BIN_DIR"
  export MOCK_CLAUDE_ARGS_FILE MOCK_GIT_ARGS_FILE MOCK_NOTIFY_FILE
  make_mock_claude "$BIN_DIR"
  make_mock_git "$BIN_DIR"
  export PATH="$BIN_DIR:$PATH"
  make_extractor_env "$SCRIPTS_DIR" "$HOME_DIR" "$WORKSPACE_DIR" "$BIN_DIR/claude" >/dev/null
}

_load_validate_env() {
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

_load_misc_fns() {
  source /dev/stdin <<'EOF'
load_env() {
    if [ -f "$ENV_FILE" ]; then
        _validate_env_file "$ENV_FILE"
        set -a
        source "$ENV_FILE"
        set +a
    fi
}

is_work_hours() {
    local hour
    hour=$(date +%H)
    [ "$hour" -ge 7 ] && [ "$hour" -le 23 ]
}
EOF
}

@test "_validate_env_file: успех с корректным env" {
  _load_validate_env
  printf 'WORKSPACE_DIR=/tmp\nCLAUDE_PATH=/bin/claude\n' > "$TEST_DIR/ok.env"
  run _validate_env_file "$TEST_DIR/ok.env"
  assert_success
}

@test "_validate_env_file: ошибка при eval" {
  _load_validate_env
  printf 'WORKSPACE_DIR=/tmp\neval "rm -rf /"\n' > "$TEST_DIR/bad.env"
  run _validate_env_file "$TEST_DIR/bad.env"
  assert_failure
  assert_output --partial 'dangerous patterns'
}

@test "_validate_env_file: ошибка при source" {
  _load_validate_env
  printf 'source /tmp/x\n' > "$TEST_DIR/source.env"
  run _validate_env_file "$TEST_DIR/source.env"
  assert_failure
}

@test "load_env: загружает переменные окружения" {
  _load_validate_env
  _load_misc_fns
  ENV_FILE="$TEST_DIR/load.env"
  printf 'WORKSPACE_DIR=/tmp/ws\nCLAUDE_PATH=/bin/claude\n' > "$ENV_FILE"
  load_env
  assert_equal "$WORKSPACE_DIR" "/tmp/ws"
  assert_equal "$CLAUDE_PATH" "/bin/claude"
}

@test "is_work_hours: true в рабочее время" {
  _load_misc_fns
  date() { printf '12\n'; }
  export -f date
  run is_work_hours
  assert_success
}

@test "is_work_hours: false ночью" {
  _load_misc_fns
  date() { printf '03\n'; }
  export -f date
  run is_work_hours
  assert_failure
}

@test "запуск без аргументов: usage и exit 1" {
  run env HOME="$HOME_DIR" PATH="$PATH" bash "$SCRIPT"
  assert_failure
  assert_output --partial 'Usage:'
  assert_output --partial 'inbox-check'
}

@test "inbox-check: SKIP вне рабочих часов" {
  cat > "$BIN_DIR/date" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "+%H" ]; then echo 03; else /usr/bin/date "$@"; fi
EOF
  chmod +x "$BIN_DIR/date"
  run env HOME="$HOME_DIR" PATH="$BIN_DIR:$PATH" bash "$SCRIPT" inbox-check
  assert_success
  assert_output --partial 'SKIP: inbox-check outside work hours'
}

@test "inbox-check: SKIP если captures.md не найден" {
  run env HOME="$HOME_DIR" PATH="$PATH" bash "$SCRIPT" inbox-check
  assert_success
  assert_output --partial 'captures.md not found'
}

@test "inbox-check: SKIP если нет pending captures" {
  mkdir -p "$WORKSPACE_DIR/DS-strategy/inbox"
  cat > "$WORKSPACE_DIR/DS-strategy/inbox/captures.md" <<'EOF'
### A
[processed 2026-03-19]
EOF
  run env HOME="$HOME_DIR" PATH="$PATH" bash "$SCRIPT" inbox-check
  assert_success
  assert_output --partial 'No pending captures'
}

@test "run_claude: ошибка если prompt файл отсутствует" {
  mv "$PROMPTS_DIR/inbox-check.md" "$PROMPTS_DIR/inbox-check.md.bak"
  mkdir -p "$WORKSPACE_DIR/DS-strategy/inbox"
  cat > "$WORKSPACE_DIR/DS-strategy/inbox/captures.md" <<'EOF'
### A
pending
EOF
  run env HOME="$HOME_DIR" PATH="$PATH" bash "$SCRIPT" inbox-check
  mv "$PROMPTS_DIR/inbox-check.md.bak" "$PROMPTS_DIR/inbox-check.md"
  assert_failure
  assert_output --partial 'Command file not found'
}

@test "inbox-check: запускает AI CLI и git flow при pending captures" {
  mkdir -p "$WORKSPACE_DIR/DS-strategy/inbox" "$WORKSPACE_DIR/DS-strategy/.git"
  cat > "$WORKSPACE_DIR/DS-strategy/inbox/captures.md" <<'EOF'
### A
pending
EOF
  make_mock_notify_script "$WORKSPACE_DIR/FMT-exocortex-template/roles/synchronizer/scripts/notify.sh"
  mkdir -p "$WORKSPACE_DIR/FMT-exocortex-template/roles/synchronizer/scripts"
  run env HOME="$HOME_DIR" PATH="$PATH" bash "$SCRIPT" inbox-check
  assert_success
  run grep -- '--dangerously-skip-permissions' "$MOCK_CLAUDE_ARGS_FILE"
  assert_success
  run grep 'add inbox/captures.md inbox/extraction-reports/' "$MOCK_GIT_ARGS_FILE"
  assert_success
}

@test "run_claude: добавляет extra args в prompt" {
  source /dev/stdin <<EOF
PROMPTS_DIR="$PROMPTS_DIR"
WORKSPACE="$WORKSPACE_DIR"
LOG_FILE="$TEST_DIR/log.txt"
AI_CLI="$BIN_DIR/claude"
AI_CLI_PROMPT_FLAG="-p"
AI_CLI_EXTRA_FLAGS="--flag-a --flag-b"
log() { :; }
notify() { :; }
run_claude() {
    local command_file="\$1"
    local extra_args="\$2"
    local command_path="$PROMPTS_DIR/\$command_file.md"
    if [ ! -f "\$command_path" ]; then exit 1; fi
    local prompt
    prompt=\$(cat "\$command_path")
    if [ -n "\$extra_args" ]; then
        prompt="\$prompt

## Дополнительный контекст

\$extra_args"
    fi
    cd "$WORKSPACE"
    "\$AI_CLI" \$AI_CLI_EXTRA_FLAGS "\$AI_CLI_PROMPT_FLAG" "\$prompt" >> "\$LOG_FILE" 2>&1
}
EOF
  mkdir -p "$WORKSPACE_DIR"
  run run_claude 'on-demand' 'extra context here'
  assert_success
  run grep 'Дополнительный контекст' "$MOCK_CLAUDE_ARGS_FILE"
  assert_success
  run grep 'extra context here' "$MOCK_CLAUDE_ARGS_FILE"
  assert_success
}

@test "audit: запускает knowledge-audit prompt" {
  run env HOME="$HOME_DIR" PATH="$PATH" bash "$SCRIPT" audit
  assert_success
  run grep 'Knowledge Audit' "$MOCK_CLAUDE_ARGS_FILE"
  assert_success
}

@test "session-close: запускает session-close prompt" {
  run env HOME="$HOME_DIR" PATH="$PATH" bash "$SCRIPT" session-close
  assert_success
  run grep 'сессии' "$MOCK_CLAUDE_ARGS_FILE"
  assert_success
}

@test "on-demand: запускает on-demand prompt" {
  run env HOME="$HOME_DIR" PATH="$PATH" bash "$SCRIPT" on-demand
  assert_success
  run grep 'On-Demand Extraction' "$MOCK_CLAUDE_ARGS_FILE"
  assert_success
}
