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
  GIT_LOG="$TEST_DIR/git.log"
  export HOME="$HOME_DIR"
  mkdir -p "$HOME_DIR" "$EXO_DIR/memory" "$EXO_DIR/roles/strategist" "$EXO_DIR/.claude" "$BIN_DIR"
  mkdir -p "$HOME_DIR/.workspace"

  cp "${BATS_TEST_DIRNAME}/../update.sh" "$EXO_DIR/update.sh"
  cat > "$EXO_DIR/CLAUDE.md" <<'EOF'
# test
EOF
  cat > "$EXO_DIR/CHANGELOG.md" <<'EOF'
## [0.9.0] - 2026-03-19

- new thing

## [0.8.0] - 2026-03-18

- old thing
EOF
  cat > "$EXO_DIR/ONTOLOGY.md" <<'EOF'
## Platform
base
<!-- USER-SPACE -->
user old
EOF
  cat > "$WORKSPACE_DIR/ONTOLOGY.md" <<'EOF'
## Platform
old base
<!-- USER-SPACE -->
user preserved
EOF
  cat > "$EXO_DIR/.claude/settings.local.json" <<'EOF'
{
  "mcpServers": {"a": {"command": "a"}},
  "permissions": {"allow": ["Read", "Write"]}
}
EOF
  mkdir -p "$WORKSPACE_DIR/.claude"
  cat > "$WORKSPACE_DIR/.claude/settings.local.json" <<'EOF'
{
  "mcpServers": {"old": {"command": "old"}},
  "permissions": {"allow": ["Read", "Bash"]}
}
EOF
  cat > "$EXO_DIR/memory/foo.md" <<'EOF'
memory foo
EOF
  mkdir -p "$HOME_DIR/.claude/projects/-$(echo "$WORKSPACE_DIR" | tr '/' '-')/memory"
  cat > "$HOME_DIR/.claude/projects/-$(echo "$WORKSPACE_DIR" | tr '/' '-')/memory/foo.md" <<'EOF'
old memory
EOF
  cat > "$HOME_DIR/.workspace/env" <<EOF
WORKSPACE_DIR=$WORKSPACE_DIR
CLAUDE_PATH=/usr/bin/false
EOF
  chmod +x "$EXO_DIR/update.sh"

  cat > "$EXO_DIR/roles/strategist/install.sh" <<'EOF'
#!/usr/bin/env bash
echo strategist-install >> "$ROLE_INSTALL_LOG"
EOF
  chmod +x "$EXO_DIR/roles/strategist/install.sh"

  export ROLE_INSTALL_LOG="$TEST_DIR/role-install.log"
  export MOCK_LOCAL_SHA="1111111"
  export MOCK_UPSTREAM_SHA="2222222"
  export MOCK_BASE_SHA="0000000"
  export MOCK_COMMITS_BEHIND="2"
  export MOCK_REMOTE_HAS_UPSTREAM="1"
  export MOCK_CHANGED_FILES="roles/strategist/install.sh"
  export GIT_LOG

  cat > "$BIN_DIR/git" <<'EOF'
#!/usr/bin/env bash
printf '%s
' "$*" >> "$GIT_LOG"
case "$*" in
  "remote")
    if [ "${MOCK_REMOTE_HAS_UPSTREAM:-1}" = "1" ]; then
      printf 'origin
upstream
'
    else
      printf 'origin
'
    fi
    ;;
  "remote add upstream https://github.com/TserenTserenov/FMT-exocortex-template.git") exit 0 ;;
  "fetch upstream main") exit 0 ;;
  "rev-parse HEAD") printf '%s
' "$MOCK_LOCAL_SHA" ;;
  "rev-parse upstream/main") printf '%s
' "$MOCK_UPSTREAM_SHA" ;;
  "merge-base HEAD upstream/main") printf '%s
' "$MOCK_BASE_SHA" ;;
  "rev-list --count HEAD..upstream/main") printf '%s
' "$MOCK_COMMITS_BEHIND" ;;
  "log --oneline HEAD..upstream/main") printf 'abc1234 one
def5678 two
' ;;
  "diff --stat HEAD..upstream/main") printf ' update.sh | 4 ++--
' ;;
  stash\ push\ -m*) exit 0 ;;
  "stash pop") exit 0 ;;
  "merge upstream/main --no-edit") exit 0 ;;
  "diff --name-only 1111111..2222222") printf '%s
' "$MOCK_CHANGED_FILES" ;;
  "push") exit 0 ;;
  *)
    if [[ "$*" == *"diff --quiet"* ]]; then
      exit 1
    elif [[ "$*" == *"add -A"* ]]; then
      exit 0
    elif [[ "$*" == *"commit -m chore: re-substitute placeholders after upstream merge"* ]]; then
      exit 0
    else
      exit 0
    fi
    ;;
esac
EOF
  chmod +x "$BIN_DIR/git"
  export PATH="$BIN_DIR:$PATH"
}

@test "update.sh: ошибка вне корня экзокортекса" {
  local bad_dir="$TEST_DIR/bad"
  mkdir -p "$bad_dir"
  cp "${BATS_TEST_DIRNAME}/../update.sh" "$bad_dir/update.sh"
  run env HOME="$HOME_DIR" PATH="$PATH" bash "$bad_dir/update.sh"
  assert_failure
  assert_output --partial 'Cannot find exocortex directory'
}

@test "update.sh --check: показывает новые коммиты и не применяет merge" {
  run env HOME="$HOME_DIR" PATH="$PATH" bash "$EXO_DIR/update.sh" --check
  assert_success
  assert_output --partial '2 new commits from upstream'
  assert_output --partial 'abc1234 one'
  assert_output --partial "Run 'update.sh' to apply these changes."
  run grep 'merge upstream/main --no-edit' "$GIT_LOG"
  assert_failure
}

@test "update.sh: already up to date -> exit 0" {
  export MOCK_UPSTREAM_SHA="$MOCK_LOCAL_SHA"
  run env HOME="$HOME_DIR" PATH="$PATH" bash "$EXO_DIR/update.sh" --check
  assert_success
  assert_output --partial 'Already up to date.'
}

@test "update.sh --dry-run: показывает merge, placeholders и reinstall role" {
  cat > "$EXO_DIR/placeholder.md" <<'EOF'
root={{WORKSPACE_DIR}}
EOF
  run env HOME="$HOME_DIR" PATH="$PATH" bash "$EXO_DIR/update.sh" --dry-run
  assert_success
  assert_output --partial '[DRY RUN] Would merge 2 commits'
  assert_output --partial 'Would re-substitute {{WORKSPACE_DIR}}'
  assert_output --partial '[DRY RUN] Would reinstall: strategist'
  assert_output --partial '[DRY RUN] No changes made.'
}

@test "update.sh: реально подставляет {{WORKSPACE_DIR}} только в совпавших файлах" {
  cat > "$EXO_DIR/placeholder.md" <<'EOF'
root={{WORKSPACE_DIR}}
EOF
  cat > "$EXO_DIR/untouched.md" <<'EOF'
root=/already/resolved
EOF
  run env HOME="$HOME_DIR" PATH="$PATH" bash "$EXO_DIR/update.sh"
  assert_success
  run grep "$WORKSPACE_DIR" "$EXO_DIR/placeholder.md"
  assert_success
  run grep '{{WORKSPACE_DIR}}' "$EXO_DIR/placeholder.md"
  assert_failure
  run cat "$EXO_DIR/untouched.md"
  assert_output 'root=/already/resolved'
}

@test "update.sh: merge ONTOLOGY preserves USER-SPACE" {
  run env HOME="$HOME_DIR" PATH="$PATH" bash "$EXO_DIR/update.sh"
  assert_success
  run grep 'user preserved' "$WORKSPACE_DIR/ONTOLOGY.md"
  assert_success
  run grep 'base' "$WORKSPACE_DIR/ONTOLOGY.md"
  assert_success
}

@test "update.sh: merges settings.local.json preserving user permissions" {
  run env HOME="$HOME_DIR" PATH="$PATH" bash "$EXO_DIR/update.sh"
  assert_success
  run python3 - <<PY
import json
with open("$WORKSPACE_DIR/.claude/settings.local.json") as f:
    data=json.load(f)
assert sorted(data['permissions']['allow']) == ['Bash','Read','Write']
assert 'a' in data['mcpServers']
print('ok')
PY
  assert_success
  assert_output 'ok'
}

@test "update.sh: обновляет workspace CLAUDE.md и memory files" {
  echo 'old' > "$WORKSPACE_DIR/CLAUDE.md"
  run env HOME="$HOME_DIR" PATH="$PATH" bash "$EXO_DIR/update.sh"
  assert_success
  run cat "$WORKSPACE_DIR/CLAUDE.md"
  assert_output '# test'
  run cat "$HOME_DIR/.claude/projects/-$(echo "$WORKSPACE_DIR" | tr '/' '-')/memory/foo.md"
  assert_output 'memory foo'
}

@test "update.sh: reinstalls changed role install.sh" {
  run env HOME="$HOME_DIR" PATH="$PATH" bash "$EXO_DIR/update.sh"
  assert_success
  run grep 'strategist-install' "$ROLE_INSTALL_LOG"
  assert_success
}

@test "update.sh: adds upstream remote when missing" {
  export MOCK_REMOTE_HAS_UPSTREAM="0"
  run env HOME="$HOME_DIR" PATH="$PATH" bash "$EXO_DIR/update.sh" --check
  assert_success
  run grep 'remote add upstream' "$GIT_LOG"
  assert_success
}

@test "update.sh: release notes extracts latest section via awk" {
  run env HOME="$HOME_DIR" PATH="$PATH" bash "$EXO_DIR/update.sh"
  assert_success
  assert_output --partial 'new thing'
  refute_output --partial 'old thing'
}
