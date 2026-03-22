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
  LOG_DIR="$HOME_DIR/.local/state/logs/extractor"
  CAPTURES_DIR="$WORKSPACE_DIR/DS-strategy/inbox"
  export HOME="$HOME_DIR"
  mkdir -p "$HOME_DIR/.workspace" "$BIN_DIR" "$LOG_DIR" "$CAPTURES_DIR" \
    "$EXO_DIR/roles/extractor/scripts" "$EXO_DIR/roles/extractor/prompts" \
    "$EXO_DIR/roles/extractor/lib" "$EXO_DIR/roles/shared/lib" "$EXO_DIR/lib"

  cp "${BATS_TEST_DIRNAME}/../roles/extractor/scripts/extractor.sh" "$EXO_DIR/roles/extractor/scripts/extractor.sh"
  cp -R "${BATS_TEST_DIRNAME}/../roles/extractor/lib/." "$EXO_DIR/roles/extractor/lib/"
  cp -R "${BATS_TEST_DIRNAME}/../roles/shared/lib/." "$EXO_DIR/roles/shared/lib/"
  cp -R "${BATS_TEST_DIRNAME}/../lib/." "$EXO_DIR/lib/"
  cp "${BATS_TEST_DIRNAME}/../roles/extractor/prompts/inbox-check.md" "$EXO_DIR/roles/extractor/prompts/inbox-check.md"
  cp "${BATS_TEST_DIRNAME}/../roles/extractor/prompts/knowledge-audit.md" "$EXO_DIR/roles/extractor/prompts/knowledge-audit.md"
  cp "${BATS_TEST_DIRNAME}/../roles/extractor/prompts/on-demand.md" "$EXO_DIR/roles/extractor/prompts/on-demand.md"
  cp "${BATS_TEST_DIRNAME}/../roles/extractor/prompts/session-close.md" "$EXO_DIR/roles/extractor/prompts/session-close.md"
  cat > "$EXO_DIR/CLAUDE.md" <<'EOF'
# test
EOF
  mkdir -p "$EXO_DIR/memory"
  cat > "$HOME_DIR/.workspace/env" <<EOF
WORKSPACE_DIR=$WORKSPACE_DIR
CLAUDE_PATH=$BIN_DIR/mock-ai
EOF

  export ROLE_NOTIFY_LOG="$TEST_DIR/notify.log"
  export AI_INVOCATION_LOG="$TEST_DIR/ai.log"
  export GIT_CALLS_LOG="$TEST_DIR/git.log"
  export PATH="$BIN_DIR:$PATH"

  cat > "$BIN_DIR/mock-ai" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$AI_INVOCATION_LOG"
exit 0
EOF

  cat > "$BIN_DIR/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GIT_CALLS_LOG"
case "$*" in
  *"diff --cached --quiet"*) exit 1 ;;
  *"diff --quiet origin/main..HEAD"*) exit 1 ;;
  *) exit 0 ;;
esac
EOF

  cat > "$BIN_DIR/notify-send" <<'EOF'
#!/usr/bin/env bash
printf 'notify-send %s\n' "$*" >> "$ROLE_NOTIFY_LOG"
exit 0
EOF

  chmod +x "$BIN_DIR/mock-ai" "$BIN_DIR/git" "$BIN_DIR/notify-send" "$EXO_DIR/roles/extractor/scripts/extractor.sh"

  mkdir -p "$WORKSPACE_DIR/DS-strategy/.git" "$WORKSPACE_DIR/DS-strategy/inbox/extraction-reports"
  mkdir -p "$WORKSPACE_DIR/FMT-exocortex-template/scripts"
  cat > "$WORKSPACE_DIR/FMT-exocortex-template/scripts/notify.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "$1" "$2" >> "$ROLE_NOTIFY_LOG"
exit 0
EOF
  chmod +x "$WORKSPACE_DIR/FMT-exocortex-template/scripts/notify.sh"
}

@test "extractor inbox-check: пропускает запуск вне рабочих часов" {
  cat > "$CAPTURES_DIR/captures.md" <<'EOF'
### test
capture body
EOF

  cat > "$BIN_DIR/date" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == +%H ]]; then
  printf '03\n'
elif [[ "$1" == +%Y-%m-%d ]]; then
  printf '2026-03-21\n'
else
  /bin/date "$@"
fi
EOF
  chmod +x "$BIN_DIR/date"

  run bash "$EXO_DIR/roles/extractor/scripts/extractor.sh" inbox-check

  assert_success
  assert_output --partial 'SKIP: inbox-check outside work hours'
}

@test "extractor inbox-check: пропускает при отсутствии pending captures" {
  cat > "$CAPTURES_DIR/captures.md" <<'EOF'
### item one [processed]
done
EOF

  run bash "$EXO_DIR/roles/extractor/scripts/extractor.sh" inbox-check

  assert_success
  assert_output --partial 'SKIP: No pending captures in inbox'
}

@test "extractor inbox-check: запускает AI CLI и sync DS-strategy при pending captures" {
  cat > "$CAPTURES_DIR/captures.md" <<'EOF'
### item one
capture body
EOF

  run bash "$EXO_DIR/roles/extractor/scripts/extractor.sh" inbox-check

  assert_success
  assert_output --partial 'Found 1 pending captures in inbox'
  assert_output --partial 'Completed process: inbox-check'
  run grep 'inbox-check' "$AI_INVOCATION_LOG"
  assert_success
  run grep 'add inbox/captures.md inbox/extraction-reports/' "$GIT_CALLS_LOG"
  assert_success
  run grep 'extractor inbox-check' "$ROLE_NOTIFY_LOG"
  assert_success
}

@test "extractor audit: использует knowledge-audit prompt" {
  run bash "$EXO_DIR/roles/extractor/scripts/extractor.sh" audit

  assert_success
  assert_output --partial 'Running knowledge audit'
  run grep 'Knowledge Audit' "$AI_INVOCATION_LOG"
  assert_success
}
