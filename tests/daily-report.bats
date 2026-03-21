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
  STATE_DIR="$HOME_DIR/.local/state/exocortex"
  LOG_DIR="$HOME_DIR/.local/state/logs/synchronizer"
  STRATEGIST_LOG_DIR="$HOME_DIR/.local/state/logs/strategist"
  export HOME="$HOME_DIR"

  mkdir -p "$HOME_DIR/.workspace" "$BIN_DIR" "$STATE_DIR" "$LOG_DIR" "$STRATEGIST_LOG_DIR" \
    "$EXO_DIR/roles/synchronizer/scripts" "$EXO_DIR/roles/synchronizer/lib" "$EXO_DIR/lib" \
    "$WORKSPACE_DIR/DS-strategy/current" "$WORKSPACE_DIR/DS-strategy/archive/scheduler-reports" "$WORKSPACE_DIR/DS-strategy/.git"

  cp "${BATS_TEST_DIRNAME}/../roles/synchronizer/scripts/daily-report.sh" "$EXO_DIR/roles/synchronizer/scripts/daily-report.sh"
  cp -R "${BATS_TEST_DIRNAME}/../roles/synchronizer/lib/." "$EXO_DIR/roles/synchronizer/lib/"
  cp -R "${BATS_TEST_DIRNAME}/../lib/." "$EXO_DIR/lib/"
  cat > "$EXO_DIR/CLAUDE.md" <<'EOF'
# test
EOF
  mkdir -p "$EXO_DIR/memory"

  cat > "$HOME_DIR/.workspace/env" <<EOF
WORKSPACE_DIR=$WORKSPACE_DIR
EOF

  export PATH="$BIN_DIR:$PATH"
  export GIT_CALLS_LOG="$TEST_DIR/git.log"

  cat > "$BIN_DIR/date" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  +%Y-%m-%d) printf '%s\n' '2026-03-23' ;;
  +%u) printf '%s\n' "${MOCK_DOW:-1}" ;;
  +%H) printf '%s\n' "${MOCK_HOUR:-23}" ;;
  +%V) printf '%s\n' '13' ;;
  +%s) printf '%s\n' '1711238400' ;;
  +%H:%M:%S) printf '%s\n' '23:00:00' ;;
  *) /bin/date "$@" ;;
esac
EOF

  cat > "$BIN_DIR/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GIT_CALLS_LOG"
case "$*" in
  *"diff --cached --quiet"*) exit 1 ;;
  *) exit 0 ;;
esac
EOF

  chmod +x "$BIN_DIR/date" "$BIN_DIR/git" "$EXO_DIR/roles/synchronizer/scripts/daily-report.sh"
}

@test "daily-report --dry-run: renders healthy report" {
  export MOCK_DOW=1
  export MOCK_HOUR=23
  echo '08:00:00' > "$STATE_DIR/synchronizer-code-scan-2026-03-23"
  echo '08:05:00' > "$STATE_DIR/strategist-morning-2026-03-23"
  echo '23:01:00' > "$STATE_DIR/strategist-note-review-2026-03-23"
  echo '2026-03-23 00:10:00' > "$STATE_DIR/strategist-week-review-W13"
  echo '1711234800' > "$STATE_DIR/extractor-inbox-check-last"

  run bash "$EXO_DIR/roles/synchronizer/scripts/daily-report.sh" --dry-run

  assert_success
  assert_output --partial '🟢 Среда готова к работе'
  assert_output --partial '| 1 | Сканирование кода | **✅** | 08:00:00 |'
  assert_output --partial '| 5 | Проверка входящих | **✅** | 3600 сек назад |'
}

@test "daily-report: writes report and archives old reports" {
  export MOCK_DOW=2
  export MOCK_HOUR=8
  echo '08:00:00' > "$STATE_DIR/synchronizer-code-scan-2026-03-23"
  echo '08:05:00' > "$STATE_DIR/strategist-morning-2026-03-23"
  echo '1711234800' > "$STATE_DIR/extractor-inbox-check-last"
  echo 'old report' > "$WORKSPACE_DIR/DS-strategy/current/SchedulerReport 2026-03-22.md"

  run bash "$EXO_DIR/roles/synchronizer/scripts/daily-report.sh"

  assert_success
  assert_file_exist "$WORKSPACE_DIR/DS-strategy/current/SchedulerReport 2026-03-23.md"
  assert_file_exist "$WORKSPACE_DIR/DS-strategy/archive/scheduler-reports/SchedulerReport 2026-03-22.md"
  run grep 'commit -m auto: scheduler report 2026-03-23' "$GIT_CALLS_LOG"
  assert_success
}
