#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'

setup() {
  TEST_DIR="$BATS_TEST_TMPDIR"
  HOME_DIR="$TEST_DIR/home"
  WORKSPACE_ROOT="$TEST_DIR/workspace"
  STRATEGY_DIR="$WORKSPACE_ROOT/DS-strategy"
  EXO_DIR="$WORKSPACE_ROOT/FMT-exocortex-template"
  BIN_DIR="$TEST_DIR/bin"
  LOG_DIR="$HOME_DIR/.local/state/logs/strategist"
  PROJECT_SLUG="$(printf '%s' "$WORKSPACE_ROOT" | tr '/' '-')"

  export HOME="$HOME_DIR"
  mkdir -p "$HOME_DIR/.workspace" "$HOME_DIR/.claude/projects/$PROJECT_SLUG/memory" \
    "$HOME_DIR/.local/state/logs/synchronizer" "$HOME_DIR/.config/aist" \
    "$STRATEGY_DIR/.git" "$STRATEGY_DIR/inbox" "$STRATEGY_DIR/archive/notes" \
    "$EXO_DIR/roles/strategist/scripts" "$EXO_DIR/roles/strategist/prompts" \
    "$EXO_DIR/roles/strategist/lib" "$EXO_DIR/roles/shared/lib" "$EXO_DIR/lib" \
    "$EXO_DIR/roles/synchronizer/scripts" "$EXO_DIR/scripts" "$BIN_DIR" "$LOG_DIR"

  cp "${BATS_TEST_DIRNAME}/../roles/strategist/scripts/strategist.sh" "$EXO_DIR/roles/strategist/scripts/strategist.sh"
  cp "${BATS_TEST_DIRNAME}/../roles/strategist/scripts/cleanup-processed-notes.sh" "$EXO_DIR/roles/strategist/scripts/cleanup-processed-notes.sh"
  cp -R "${BATS_TEST_DIRNAME}/../roles/strategist/lib/." "$EXO_DIR/roles/strategist/lib/"
  cp -R "${BATS_TEST_DIRNAME}/../roles/shared/lib/." "$EXO_DIR/roles/shared/lib/"
  cp -R "${BATS_TEST_DIRNAME}/../lib/." "$EXO_DIR/lib/"
  cp "${BATS_TEST_DIRNAME}/../roles/strategist/prompts/day-plan.md" "$EXO_DIR/roles/strategist/prompts/day-plan.md"
  cp "${BATS_TEST_DIRNAME}/../roles/strategist/prompts/session-prep.md" "$EXO_DIR/roles/strategist/prompts/session-prep.md"
  cp "${BATS_TEST_DIRNAME}/../roles/strategist/prompts/week-review.md" "$EXO_DIR/roles/strategist/prompts/week-review.md"
  cat > "$EXO_DIR/roles/strategist/prompts/note-review.md" <<'EOF'
Test note review prompt
EOF
  cat > "$EXO_DIR/CLAUDE.md" <<'EOF'
# test
EOF
  mkdir -p "$EXO_DIR/memory"

  cat > "$HOME_DIR/.workspace/env" <<EOF
WORKSPACE_DIR=$WORKSPACE_ROOT
CLAUDE_PATH=$BIN_DIR/mock-claude
EOF
  cat > "$HOME_DIR/.claude/projects/$PROJECT_SLUG/memory/day-rhythm-config.yaml" <<'EOF'
strategy_day: monday
EOF
  cat > "$STRATEGY_DIR/inbox/fleeting-notes.md" <<'EOF'
---
type: notes
---
---
**Новая заметка**
keep me
---
EOF

  export CLAUDE_INVOCATION_LOG="$TEST_DIR/claude.log"
  export GIT_CALLS_LOG="$TEST_DIR/git.log"
  export NOTIFY_LOG="$TEST_DIR/notify.log"
  export PATH="$BIN_DIR:$PATH"

  cat > "$BIN_DIR/mock-claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CLAUDE_INVOCATION_LOG"
exit 0
EOF
  cat > "$BIN_DIR/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GIT_CALLS_LOG"
case "$*" in
  *"diff --quiet origin/main..HEAD"*) exit 0 ;;
  *"diff --quiet -- inbox/fleeting-notes.md archive/notes/Notes-Archive.md"*) exit 0 ;;
  *"log --oneline -1 --since=1 hour ago --grep=week-review"*) exit 1 ;;
  *) exit 0 ;;
esac
EOF
  cat > "$BIN_DIR/notify-send" <<'EOF'
#!/usr/bin/env bash
printf 'notify-send %s\n' "$*" >> "$NOTIFY_LOG"
exit 0
EOF
  cat > "$BIN_DIR/date" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  +%u) printf '%s\n' "${MOCK_DAY_OF_WEEK:-1}" ;;
  +%Y-%m-%d) printf '%s\n' "2026-03-23" ;;
  +%H:%M:%S) printf '%s\n' '04:00:00' ;;
  +%s) printf '%s\n' '1711152000' ;;
  *) /bin/date "$@" ;;
esac
EOF
  cat > "$EXO_DIR/scripts/notify.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "$1" "$2" >> "$NOTIFY_LOG"
exit 0
EOF

  chmod +x "$BIN_DIR/mock-claude" "$BIN_DIR/git" "$BIN_DIR/notify-send" "$BIN_DIR/date" \
    "$EXO_DIR/scripts/notify.sh" \
    "$EXO_DIR/roles/strategist/scripts/strategist.sh" \
    "$EXO_DIR/roles/strategist/scripts/cleanup-processed-notes.sh"
}

@test "strategist morning: strategy day runs session-prep" {
  export MOCK_DAY_OF_WEEK=1

  run bash "$EXO_DIR/roles/strategist/scripts/strategist.sh" morning

  assert_success
  assert_output --partial 'Strategy day (monday): running session prep'
  run grep 'session-prep' "$CLAUDE_INVOCATION_LOG"
  assert_success
}

@test "strategist morning: non-strategy day runs day-plan" {
  export MOCK_DAY_OF_WEEK=2

  run bash "$EXO_DIR/roles/strategist/scripts/strategist.sh" morning

  assert_success
  assert_output --partial 'Morning: running day plan'
  run grep 'Прочитай \[Протокол Open' "$CLAUDE_INVOCATION_LOG"
  assert_success
}

@test "strategist week-review: executes week-review prompt" {
  export MOCK_DAY_OF_WEEK=1

  run bash "$EXO_DIR/roles/strategist/scripts/strategist.sh" week-review

  assert_success
  assert_output --partial 'Sunday: running week review'
  run grep 'Week Review' "$CLAUDE_INVOCATION_LOG"
  assert_success
}

@test "strategist note-review: executes note-review prompt and cleanup script" {
  export MOCK_DAY_OF_WEEK=1

  run bash "$EXO_DIR/roles/strategist/scripts/strategist.sh" note-review

  assert_success
  assert_output --partial 'Evening: running note review'
  assert_output --partial 'Running deterministic cleanup...'
  run grep 'Test note review prompt' "$CLAUDE_INVOCATION_LOG"
  assert_success
}
