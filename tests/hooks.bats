#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'

ROOT="${BATS_TEST_DIRNAME}/.."
PRECOMPACT="${ROOT}/.claude/hooks/precompact-checkpoint.sh"
PROTO_REMINDER="${ROOT}/.claude/hooks/protocol-completion-reminder.sh"
WAKATIME="${ROOT}/.claude/hooks/wakatime-heartbeat.sh"
WP_GATE="${ROOT}/.claude/hooks/wp-gate-reminder.sh"

setup() {
  TEST_DIR="$BATS_TEST_TMPDIR"
  BIN_DIR="$TEST_DIR/bin"
  HOME_DIR="$TEST_DIR/home"
  CALLS="$TEST_DIR/calls.log"
  mkdir -p "$BIN_DIR" "$HOME_DIR/.wakatime"
  export HOME="$HOME_DIR"
  export PATH="$BIN_DIR:$PATH"

  cat > "$BIN_DIR/jq" <<'EOF'
#!/usr/bin/env python3
import json, sys
args = sys.argv[1:]
expr = args[-1]
data = json.load(sys.stdin)
mapping = {
  '.cwd // empty': data.get('cwd', ''),
  '.hook_event_name // empty': data.get('hook_event_name', ''),
  '.tool_name // empty': data.get('tool_name', ''),
  '.tool_input.file_path // empty': data.get('tool_input', {}).get('file_path', ''),
}
print(mapping.get(expr, ''))
EOF
  chmod +x "$BIN_DIR/jq"

  cat > "$BIN_DIR/git" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"config --local remote.origin.url"* ]]; then
  printf '%s\n' "git@github.com:abcdef0101/FMT-exocortex-template.git"
else
  exit 0
fi
EOF
  chmod +x "$BIN_DIR/git"

  cat > "$HOME_DIR/.wakatime/wakatime-cli" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
exit 0
EOF
  chmod +x "$HOME_DIR/.wakatime/wakatime-cli"
  export CALLS
}

@test "wp-gate hook: always returns additionalContext JSON" {
  run bash "$WP_GATE"
  assert_success
  assert_output --partial 'additionalContext'
  assert_output --partial 'WP GATE'
}

@test "precompact hook: returns PRECOMPACT reminder JSON" {
  run bash "$PRECOMPACT" <<'EOF'
{"cwd":"/tmp/project"}
EOF
  assert_success
  assert_output --partial 'additionalContext'
  assert_output --partial 'PRECOMPACT'
}

@test "protocol reminder: emits reminder for Read on protocol file" {
  run bash "$PROTO_REMINDER" <<'EOF'
{"tool_name":"Read","tool_input":{"file_path":"/tmp/memory/protocol-open.md"}}
EOF
  assert_success
  assert_output --partial 'additionalContext'
  assert_output --partial 'protocol-open'
}

@test "protocol reminder: returns empty JSON for non-protocol read" {
  run bash "$PROTO_REMINDER" <<'EOF'
{"tool_name":"Read","tool_input":{"file_path":"/tmp/README.md"}}
EOF
  assert_success
  assert_output '{}'
}

@test "protocol reminder: returns empty JSON for non-Read tool" {
  run bash "$PROTO_REMINDER" <<'EOF'
{"tool_name":"Edit","tool_input":{"file_path":"/tmp/memory/protocol-open.md"}}
EOF
  assert_success
  assert_output '{}'
}

@test "wakatime hook: falls back to folder basename when no cwd" {
  run bash "$WAKATIME" <<'EOF'
{"cwd":"","hook_event_name":"UserPromptSubmit","tool_name":""}
EOF
  assert_success
}

@test "wakatime hook: PostToolUse Read -> category code reviewing" {
  local proj="$TEST_DIR/project-a"
  mkdir -p "$proj"
  run bash "$WAKATIME" <<EOF
{"cwd":"$proj","hook_event_name":"PostToolUse","tool_name":"Read"}
EOF
  assert_success
  sleep 0.1
  run grep -- '--category code reviewing' "$CALLS"
  assert_success
}

@test "wakatime hook: PostToolUse Edit -> category coding" {
  local proj="$TEST_DIR/project-b"
  mkdir -p "$proj"
  run bash "$WAKATIME" <<EOF
{"cwd":"$proj","hook_event_name":"PostToolUse","tool_name":"Edit"}
EOF
  assert_success
  sleep 0.1
  run grep -- '--category coding' "$CALLS"
  assert_success
}

@test "wakatime hook: PostToolUse WebFetch -> category researching" {
  local proj="$TEST_DIR/project-c"
  mkdir -p "$proj"
  run bash "$WAKATIME" <<EOF
{"cwd":"$proj","hook_event_name":"PostToolUse","tool_name":"WebFetch"}
EOF
  assert_success
  sleep 0.1
  run grep -- '--category researching' "$CALLS"
  assert_success
}

@test "wakatime hook: project name derived from git remote" {
  local proj="$TEST_DIR/project-d"
  mkdir -p "$proj"
  run bash "$WAKATIME" <<EOF
{"cwd":"$proj","hook_event_name":"UserPromptSubmit","tool_name":""}
EOF
  assert_success
  sleep 0.1
  run grep -- '--project FMT-exocortex-template' "$CALLS"
  assert_success
}
