#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'

SCRIPT="${BATS_TEST_DIRNAME}/../setup/optional/setup-calendar.sh"

setup() {
  TEST_DIR="$BATS_TEST_TMPDIR"
  HOME_DIR="$TEST_DIR/home"
  WORKSPACE_DIR="$TEST_DIR/workspace"
  BIN_DIR="$TEST_DIR/bin"
  CALLS="$TEST_DIR/calls.log"
  mkdir -p "$HOME_DIR" "$WORKSPACE_DIR" "$BIN_DIR"
  export HOME="$HOME_DIR"
  export IWE_WORKSPACE="$WORKSPACE_DIR"
  export PATH="$BIN_DIR:$PATH"
  export CALLS
  cat > "$WORKSPACE_DIR/.gitignore" <<'EOF'
.env
EOF
  cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >> "$CALLS"
outfile=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-o" ]; then
    outfile="$2"
    shift 2
  else
    shift
  fi
done
printf '{"installed":"ok"}\n' > "$outfile"
EOF
  chmod +x "$BIN_DIR/curl"
  cat > "$BIN_DIR/gh" <<'EOF'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$CALLS"
printf '{"installed":"via-gh"}\n'
EOF
  chmod +x "$BIN_DIR/gh"
  cat > "$BIN_DIR/npx" <<'EOF'
#!/usr/bin/env bash
printf 'npx %s\n' "$*" >> "$CALLS"
exit 0
EOF
  chmod +x "$BIN_DIR/npx"
}

@test "setup-calendar: creates .secrets and .mcp.json" {
  run bash -c "printf '\n' | HOME='$HOME_DIR' IWE_WORKSPACE='$WORKSPACE_DIR' PATH='$PATH' bash '$SCRIPT'"
  assert_success
  assert_dir_exist "$WORKSPACE_DIR/.secrets"
  assert_file_exist "$WORKSPACE_DIR/.secrets/gcp-oauth.keys.json"
  assert_file_exist "$WORKSPACE_DIR/.mcp.json"
}

@test "setup-calendar: appends .secrets/ to .gitignore" {
  run bash -c "printf '\n' | HOME='$HOME_DIR' IWE_WORKSPACE='$WORKSPACE_DIR' PATH='$PATH' bash '$SCRIPT'"
  assert_success
  run grep '^\.secrets/$' "$WORKSPACE_DIR/.gitignore"
  assert_success
}

@test "setup-calendar: does not duplicate .secrets/ in .gitignore" {
  echo '.secrets/' >> "$WORKSPACE_DIR/.gitignore"
  run bash -c "printf '\n' | HOME='$HOME_DIR' IWE_WORKSPACE='$WORKSPACE_DIR' PATH='$PATH' bash '$SCRIPT'"
  assert_success
  run bash -c "grep -c '^\.secrets/$' '$WORKSPACE_DIR/.gitignore'"
  assert_output '1'
}

@test "setup-calendar: respects --account flag" {
  run bash -c "printf '\n' | HOME='$HOME_DIR' IWE_WORKSPACE='$WORKSPACE_DIR' PATH='$PATH' bash '$SCRIPT' --account work"
  assert_success
  run grep -- '--account work' "$CALLS"
  assert_success
}

@test "setup-calendar: falls back to gh when curl fails" {
  cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$BIN_DIR/curl"
  run bash -c "printf '\n' | HOME='$HOME_DIR' IWE_WORKSPACE='$WORKSPACE_DIR' PATH='$PATH' bash '$SCRIPT'"
  assert_success
  run grep '^gh gist view' "$CALLS"
  assert_success
}

@test "setup-calendar: fails when curl fails and gh invocation also fails" {
  cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$BIN_DIR/curl"
  cat > "$BIN_DIR/gh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$BIN_DIR/gh"
  run bash -c "printf '\n' | HOME='$HOME_DIR' IWE_WORKSPACE='$WORKSPACE_DIR' PATH='$PATH' bash '$SCRIPT'"
  assert_failure
  assert_output --partial 'curl не смог скачать, пробую через gh'
}

@test "setup-calendar: keeps existing google-calendar entry" {
  cat > "$WORKSPACE_DIR/.mcp.json" <<'EOF'
{"mcpServers":{"google-calendar":{"command":"npx"}}}
EOF
  run bash -c "printf '\n' | HOME='$HOME_DIR' IWE_WORKSPACE='$WORKSPACE_DIR' PATH='$PATH' bash '$SCRIPT'"
  assert_success
  assert_output --partial 'google-calendar уже в .mcp.json'
}

@test "setup-calendar: runs npx auth after prompt" {
  run bash -c "printf '\n' | HOME='$HOME_DIR' IWE_WORKSPACE='$WORKSPACE_DIR' PATH='$PATH' bash '$SCRIPT'"
  assert_success
  run grep 'npx -y @cocal/google-calendar-mcp auth --account personal' "$CALLS"
  assert_success
}
