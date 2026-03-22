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
  export HOME="$HOME_DIR"

  mkdir -p "$HOME_DIR/.workspace" "$BIN_DIR" "$EXO_DIR/scripts/templates" \
    "$EXO_DIR/roles/synchronizer/scripts" "$EXO_DIR/roles/synchronizer/lib" "$EXO_DIR/lib" "$EXO_DIR/scripts" \
    "$WORKSPACE_DIR/DS-strategy/.git" "$WORKSPACE_DIR/DS-strategy/current" "$WORKSPACE_DIR/DS-alpha/.git" "$WORKSPACE_DIR/DS-beta/.git"

  cp "${BATS_TEST_DIRNAME}/../scripts/notify.sh" "$EXO_DIR/scripts/notify.sh"
  cp "${BATS_TEST_DIRNAME}/../roles/synchronizer/scripts/code-scan.sh" "$EXO_DIR/roles/synchronizer/scripts/code-scan.sh"
  cp -R "${BATS_TEST_DIRNAME}/../scripts/templates/." "$EXO_DIR/scripts/templates/"
  cp -R "${BATS_TEST_DIRNAME}/../roles/synchronizer/lib/." "$EXO_DIR/roles/synchronizer/lib/"
  cp -R "${BATS_TEST_DIRNAME}/../lib/." "$EXO_DIR/lib/"
  cat > "$EXO_DIR/CLAUDE.md" <<'EOF'
# test
EOF
  mkdir -p "$EXO_DIR/memory"

  cat > "$HOME_DIR/.workspace/env" <<EOF
WORKSPACE_DIR=$WORKSPACE_DIR
TELEGRAM_BOT_TOKEN=test-token
TELEGRAM_CHAT_ID=123
EOF

  export PATH="$BIN_DIR:$PATH"
  export CURL_LOG="$TEST_DIR/curl.log"
  export GIT_LOG="$TEST_DIR/git.log"

  cat > "$WORKSPACE_DIR/DS-strategy/current/DayPlan 2026-03-21.md" <<'EOF'
# Day Plan: 2026-03-21
EOF

  cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_LOG"
printf '{"ok": true}'
EOF
  cat > "$BIN_DIR/date" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  +%Y-%m-%d) printf '%s\n' '2026-03-21' ;;
  *) /bin/date "$@" ;;
esac
EOF
  cat > "$BIN_DIR/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GIT_LOG"
case "$*" in
  *"DS-alpha"*) printf 'a1\na2\n' ;;
  *"DS-beta"*) printf '' ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$BIN_DIR/curl" "$BIN_DIR/date" "$BIN_DIR/git" "$EXO_DIR/scripts/notify.sh" "$EXO_DIR/roles/synchronizer/scripts/code-scan.sh"
}

@test "notify.sh: dispatches strategist template to Telegram" {
  run bash "$EXO_DIR/scripts/notify.sh" strategist note-review

  assert_success
  assert_output --partial 'Telegram notification sent: strategist/note-review'
  run grep 'api.telegram.org' "$CURL_LOG"
  assert_success
}

@test "code-scan.sh --dry-run: scans downstream repos and excludes DS-strategy" {
  run bash "$EXO_DIR/roles/synchronizer/scripts/code-scan.sh" --dry-run

  assert_success
  assert_output --partial 'FOUND: DS-alpha — 2 коммитов'
  assert_output --partial 'SKIP: DS-beta — нет коммитов за 24ч'
  refute_output --partial 'DS-strategy'
}
