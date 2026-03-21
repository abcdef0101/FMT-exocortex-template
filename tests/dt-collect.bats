#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'

setup() {
  TEST_DIR="$BATS_TEST_TMPDIR"
  HOME_DIR="$TEST_DIR/home"
  WORKSPACE_DIR="$TEST_DIR/workspace"
  EXO_DIR="$WORKSPACE_DIR/FMT-exocortex-template"
  BIN_DIR="$TEST_DIR/bin"
  LOG_DIR="$HOME_DIR/.local/state/logs/synchronizer"
  export HOME="$HOME_DIR"

  mkdir -p "$HOME_DIR/.workspace" "$HOME_DIR/.config/aist" "$HOME_DIR/.claude/projects/-Users-$(whoami)-IWE/memory" \
    "$HOME_DIR/.local/state/exocortex" "$BIN_DIR" "$LOG_DIR" \
    "$EXO_DIR/roles/synchronizer/scripts" "$EXO_DIR/roles/synchronizer/lib" "$EXO_DIR/lib" \
    "$WORKSPACE_DIR/DS-strategy/inbox" "$WORKSPACE_DIR/DS-alpha/.git" "$WORKSPACE_DIR/DS-beta/.git"

  cp "${BATS_TEST_DIRNAME}/../roles/synchronizer/scripts/dt-collect.sh" "$EXO_DIR/roles/synchronizer/scripts/dt-collect.sh"
  cp "${BATS_TEST_DIRNAME}/../roles/synchronizer/scripts/dt-collect-neon.py" "$EXO_DIR/roles/synchronizer/scripts/dt-collect-neon.py"
  cp -R "${BATS_TEST_DIRNAME}/../roles/synchronizer/lib/." "$EXO_DIR/roles/synchronizer/lib/"
  cp -R "${BATS_TEST_DIRNAME}/../lib/." "$EXO_DIR/lib/"
  cat > "$EXO_DIR/CLAUDE.md" <<'EOF'
# test
EOF
  mkdir -p "$EXO_DIR/memory"

  cat > "$HOME_DIR/.workspace/env" <<EOF
WORKSPACE_DIR=$WORKSPACE_DIR
EOF
  cat > "$HOME_DIR/.config/aist/env" <<EOF
WAKATIME_API_KEY=test-key
NEON_URL=postgres://example
DT_USER_ID=user-123
EOF
  cat > "$WORKSPACE_DIR/DS-strategy/inbox/open-sessions.log" <<'EOF'
2026-03-20 11:32 | WP-17 | Opus | Test session
EOF
  cat > "$HOME_DIR/.claude/projects/-Users-$(whoami)-IWE/memory/MEMORY.md" <<'EOF'
| # | РП | Статус |
|---|----|--------|
| 1 | Test | in_progress |
| 2 | Done | done |
EOF
  echo 'marker' > "$HOME_DIR/.local/state/exocortex/code-scan-2026-03-21"

  export PATH="$BIN_DIR:$PATH"
  export CURL_LOG="$TEST_DIR/curl.log"
  export PYTHON_NEON_LOG="$TEST_DIR/neon.log"

  cat > "$BIN_DIR/date" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  +%Y-%m-%d) printf '%s\n' '2026-03-21' ;;
  +%s) printf '%s\n' '1711238400' ;;
  +%H:%M:%S) printf '%s\n' '08:00:00' ;;
  *) /bin/date "$@" ;;
esac
EOF
  cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_LOG"
printf '{"cumulative_total":{"seconds":3600},"data":[{"grand_total":{"total_seconds":3600},"projects":[{"name":"demo","total_seconds":3600}],"languages":[{"name":"Bash","total_seconds":3600}],"editors":[{"name":"VS Code","total_seconds":3600}]}]}'
EOF
  cat > "$BIN_DIR/git" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"--format=%aI"*) printf '2026-03-20T10:00:00Z\n' ;;
  *"--shortstat"*) printf ' 1 file changed, 2 insertions(+), 1 deletion(-)\n' ;;
  *"--oneline"*) printf 'abc123 test commit\n' ;;
  *) exit 0 ;;
esac
EOF
  cat > "$EXO_DIR/roles/synchronizer/scripts/notify.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "$1" "$2" >> "$PYTHON_NEON_LOG"
exit 0
EOF
  chmod +x "$BIN_DIR/date" "$BIN_DIR/curl" "$BIN_DIR/git" "$EXO_DIR/roles/synchronizer/scripts/notify.sh" "$EXO_DIR/roles/synchronizer/scripts/dt-collect.sh"
}

@test "dt-collect --dry-run: emits merged JSON" {
  run bash "$EXO_DIR/roles/synchronizer/scripts/dt-collect.sh" --dry-run

  assert_success
  assert_output --partial '2_6_coding'
  assert_output --partial '2_7_iwe'
  assert_output --partial 'scheduler_health'
}
