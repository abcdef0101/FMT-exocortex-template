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
  export HOME="$HOME_DIR"
  mkdir -p "$HOME_DIR/.workspace" "$BIN_DIR" "$STATE_DIR" "$LOG_DIR" \
    "$EXO_DIR/roles/synchronizer/scripts" "$EXO_DIR/roles/synchronizer/lib" \
    "$EXO_DIR/roles/strategist/scripts" "$EXO_DIR/roles/extractor/scripts" \
    "$EXO_DIR/roles/strategist" "$EXO_DIR/roles/extractor" \
    "$EXO_DIR/lib" "$WORKSPACE_DIR/DS-strategy/current" "$WORKSPACE_DIR/DS-strategy/archive/day-plans"

  cp "${BATS_TEST_DIRNAME}/../roles/synchronizer/scripts/scheduler.sh" "$EXO_DIR/roles/synchronizer/scripts/scheduler.sh"
  cp -R "${BATS_TEST_DIRNAME}/../roles/synchronizer/lib/." "$EXO_DIR/roles/synchronizer/lib/"
  cp -R "${BATS_TEST_DIRNAME}/../lib/." "$EXO_DIR/lib/"
  cat > "$EXO_DIR/CLAUDE.md" <<'EOF'
# test
EOF
  mkdir -p "$EXO_DIR/memory"

  cat > "$HOME_DIR/.workspace/env" <<EOF
WORKSPACE_DIR=$WORKSPACE_DIR
EOF

  export CALLS_LOG="$TEST_DIR/calls.log"
  export PATH="$BIN_DIR:$PATH"

  cat > "$BIN_DIR/date" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  +%H) printf '%s\n' "${MOCK_HOUR:-08}" ;;
  +%u) printf '%s\n' "${MOCK_DOW:-1}" ;;
  +%Y-%m-%d) printf '%s\n' '2026-03-23' ;;
  +%V) printf '%s\n' '13' ;;
  +%s) printf '%s\n' '1711152000' ;;
  +%H:%M:%S) printf '%s\n' '08:00:00' ;;
  *) /bin/date "$@" ;;
esac
EOF
  chmod +x "$BIN_DIR/date"

  cat > "$EXO_DIR/roles/strategist/role.yaml" <<'EOF'
runner: scripts/strategist.sh
EOF
  cat > "$EXO_DIR/roles/extractor/role.yaml" <<'EOF'
runner: scripts/extractor.sh
EOF

  for script in strategist extractor; do
    cat > "$EXO_DIR/roles/$script/scripts/$script.sh" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' '$script' "\$*" >> "$CALLS_LOG"
exit 0
EOF
    chmod +x "$EXO_DIR/roles/$script/scripts/$script.sh"
  done

  for script in code-scan dt-collect daily-report; do
    cat > "$EXO_DIR/roles/synchronizer/scripts/$script.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' '$script' >> "$CALLS_LOG"
exit 0
EOF
    chmod +x "$EXO_DIR/roles/synchronizer/scripts/$script.sh"
  done
}

@test "scheduler status: показывает пустое состояние" {
  run bash "$EXO_DIR/roles/synchronizer/scripts/scheduler.sh" status

  assert_success
  assert_output --partial '=== Exocortex Scheduler Status ==='
  assert_output --partial '(none)'
}

@test "scheduler dispatch: запускает strategist morning, code-scan, dt-collect, daily-report и inbox-check" {
  export MOCK_HOUR=8
  export MOCK_DOW=1

  run bash "$EXO_DIR/roles/synchronizer/scripts/scheduler.sh" dispatch

  assert_success
  run grep 'strategist morning' "$CALLS_LOG"
  assert_success
  run grep '^code-scan$' "$CALLS_LOG"
  assert_success
  run grep '^dt-collect$' "$CALLS_LOG"
  assert_success
  run grep '^daily-report$' "$CALLS_LOG"
  assert_success
  run grep 'extractor inbox-check' "$CALLS_LOG"
  assert_success
}

@test "scheduler dispatch: pre-archive переносит старый DayPlan" {
  export MOCK_HOUR=8
  export MOCK_DOW=2
  echo 'old plan' > "$WORKSPACE_DIR/DS-strategy/current/DayPlan 2026-03-22.md"

  run bash "$EXO_DIR/roles/synchronizer/scripts/scheduler.sh" dispatch

  assert_success
  assert_file_not_exist "$WORKSPACE_DIR/DS-strategy/current/DayPlan 2026-03-22.md"
  assert_file_exist "$WORKSPACE_DIR/DS-strategy/archive/day-plans/DayPlan 2026-03-22.md"
}
