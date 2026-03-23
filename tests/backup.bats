#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'

setup() {
  TEST_DIR="$BATS_TEST_TMPDIR"
  HOME_DIR="$TEST_DIR/home"
  WORKSPACE_DIR="$TEST_DIR/workspace/IWE2"
  EXO_DIR="$WORKSPACE_DIR/FMT-exocortex-template"
  BIN_DIR="$TEST_DIR/bin"

  BACKUP_SCRIPT="$EXO_DIR/roles/backup/scripts/backup.sh"
  RESTORE_SCRIPT="$EXO_DIR/roles/backup/scripts/restore.sh"
  INSTALL_SCRIPT="$EXO_DIR/roles/backup/install.sh"

  # Export everything so subprocesses (scripts + mocks) inherit it
  export HOME="$HOME_DIR"
  export WORKSPACE_DIR
  export BACKUP_GITHUB_REPO="test-user/test-backup"
  export BACKUP_PASSWORD="testpass"
  export GIT_CALLS_LOG="$TEST_DIR/git.log"
  export OPENSSL_CALLS_LOG="$TEST_DIR/openssl.log"
  export GH_CALLS_LOG="$TEST_DIR/gh.log"
  # Mock control variables — default to success
  export GIT_DIFF_EXIT=0
  export GIT_STAGED_EXIT=0
  export GIT_PUSH_EXIT=0
  export GIT_PULL_EXIT=0
  export GH_EXIT_CODE=0
  export OPENSSL_EXIT_CODE=0
  export GH_DOWNLOAD_SOURCE=""

  # Pre-create log files so grep returns exit 1 (no match) not exit 2 (file missing)
  touch "$TEST_DIR/git.log" "$TEST_DIR/openssl.log" "$TEST_DIR/gh.log"

  # Workspace structure
  mkdir -p \
    "$HOME_DIR/.local/state/logs/extractor" \
    "$HOME_DIR/.local/state/exocortex" \
    "$HOME_DIR/.claude/projects" \
    "$WORKSPACE_DIR/.claude" \
    "$WORKSPACE_DIR/memory" \
    "$EXO_DIR/roles/backup/scripts" \
    "$BIN_DIR"

  echo "# test" > "$WORKSPACE_DIR/CLAUDE.md"
  echo '{"permissions":[]}' > "$WORKSPACE_DIR/.claude/settings.local.json"

  # Claude projects directory (memory)
  local slug="${WORKSPACE_DIR//\//-}"
  mkdir -p "$HOME_DIR/.claude/projects/${slug}/memory"
  echo "# MEMORY" > "$HOME_DIR/.claude/projects/${slug}/memory/MEMORY.md"

  # Env file: ~/.IWE2/env
  mkdir -p "$HOME_DIR/.IWE2"
  cat > "$HOME_DIR/.IWE2/env" <<EOF
WORKSPACE_DIR=$WORKSPACE_DIR
BACKUP_GITHUB_REPO=test-user/test-backup
EOF

  # Copy scripts under test
  cp "${BATS_TEST_DIRNAME}/../roles/backup/scripts/backup.sh"  "$BACKUP_SCRIPT"
  cp "${BATS_TEST_DIRNAME}/../roles/backup/scripts/restore.sh" "$RESTORE_SCRIPT"
  cp "${BATS_TEST_DIRNAME}/../roles/backup/install.sh"         "$INSTALL_SCRIPT"
  chmod +x "$BACKUP_SCRIPT" "$RESTORE_SCRIPT" "$INSTALL_SCRIPT"

  export PATH="$BIN_DIR:$PATH"

  # ── Mock: git ──────────────────────────────────────────────────────────────
  cat > "$BIN_DIR/git" <<'EOF'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >> "$GIT_CALLS_LOG"
case "$*" in
  *"remote get-url origin"*)  printf 'https://github.com/test/repo.git\n' ;;
  *"diff --cached --quiet"*)  exit "${GIT_STAGED_EXIT:-0}" ;;
  *"diff --quiet"*)           exit "${GIT_DIFF_EXIT:-0}" ;;
  *"push origin"*)            exit "${GIT_PUSH_EXIT:-0}" ;;
  *"pull --rebase"*)          exit "${GIT_PULL_EXIT:-0}" ;;
esac
exit 0
EOF
  chmod +x "$BIN_DIR/git"

  # ── Mock: openssl ──────────────────────────────────────────────────────────
  # Simulate encrypt/decrypt by copying input → output (no real crypto)
  cat > "$BIN_DIR/openssl" <<'EOF'
#!/usr/bin/env bash
printf 'openssl %s\n' "$*" >> "$OPENSSL_CALLS_LOG"
in_file="" out_file=""
i=1
while [[ $i -le $# ]]; do
  case "${!i}" in
    -in)  j=$((i+1)); in_file="${!j}";  i=$((i+2)) ;;
    -out) j=$((i+1)); out_file="${!j}"; i=$((i+2)) ;;
    *)    i=$((i+1)) ;;
  esac
done
cat > /dev/null  # consume stdin (password via -pass stdin)
if [[ -n "$in_file" && -n "$out_file" && -f "$in_file" ]]; then
  cp "$in_file" "$out_file"
fi
exit "${OPENSSL_EXIT_CODE:-0}"
EOF
  chmod +x "$BIN_DIR/openssl"

  # ── Mock: gh ───────────────────────────────────────────────────────────────
  cat > "$BIN_DIR/gh" <<'EOF'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$GH_CALLS_LOG"
case "$*" in
  *"release list"*)
    printf 'backup-2026-03-23-120000\tLatest\tIWE Backup\t2026-03-23\n'
    ;;
  *"release download"*)
    if [[ -n "${GH_DOWNLOAD_SOURCE:-}" ]]; then
      args=("$@")
      dir=""
      i=0
      while [[ $i -lt ${#args[@]} ]]; do
        if [[ "${args[$i]}" == "--dir" ]]; then
          i=$((i+1)); dir="${args[$i]}"; break
        fi
        i=$((i+1))
      done
      [[ -n "$dir" ]] && cp "$GH_DOWNLOAD_SOURCE" "$dir/"
    fi
    ;;
esac
exit "${GH_EXIT_CODE:-0}"
EOF
  chmod +x "$BIN_DIR/gh"
}

# ── Helper: build a synthetic backup archive ──────────────────────────────────
# Creates a real .tar.gz (using system tar) and exports GH_DOWNLOAD_SOURCE.
_build_backup_archive() {
  local orig_workspace="${1:-$WORKSPACE_DIR}"
  local slug="${orig_workspace//\//-}"
  local stage="$TEST_DIR/archive-stage"

  mkdir -p \
    "$stage/claude-projects/memory" \
    "$stage/workspace/.claude" \
    "$stage/workspace-env" \
    "$stage/logs" \
    "$stage/exocortex"

  echo "# MEMORY"           > "$stage/claude-projects/memory/MEMORY.md"
  echo "# CLAUDE"           > "$stage/workspace/CLAUDE.md"
  echo '{"permissions":[]}' > "$stage/workspace/.claude/settings.local.json"
  echo "log entry"          > "$stage/logs/test.log"
  cat > "$stage/workspace-env/env" <<EOF
WORKSPACE_DIR=${orig_workspace}
BACKUP_GITHUB_REPO=test-user/test-backup
EOF
  cat > "$stage/meta.env" <<EOF
BACKUP_WORKSPACE_DIR=${orig_workspace}
BACKUP_WORKSPACE_NAME=IWE2
BACKUP_CLAUDE_SLUG=${slug}
BACKUP_DATE=2026-03-23
BACKUP_TIMESTAMP=2026-03-23T12:00:00
BACKUP_VERSION=1.0.0
EOF
  echo "DS-notes https://github.com/test/DS-notes.git" > "$stage/repo-list.txt"

  local archive="$TEST_DIR/iwe-backup-2026-03-23-120000.tar.gz.enc"
  (cd "$stage" && /bin/tar -czf "$archive" .)
  export GH_DOWNLOAD_SOURCE="$archive"
}

# ══════════════════════════════════════════════════════════════════════════════
# backup.sh tests
# ══════════════════════════════════════════════════════════════════════════════

@test "backup: отсутствует BACKUP_GITHUB_REPO → exit 10" {
  unset BACKUP_GITHUB_REPO
  cat > "$HOME_DIR/.IWE2/env" <<EOF
WORKSPACE_DIR=$WORKSPACE_DIR
EOF

  run bash "$BACKUP_SCRIPT"

  [ "$status" -eq 10 ]
  assert_output --partial 'BACKUP_GITHUB_REPO'
}

@test "backup: DS-*/Pack-* без remote origin → exit 11" {
  mkdir -p "$WORKSPACE_DIR/DS-notes/.git"

  cat > "$BIN_DIR/git" <<'EOF'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >> "$GIT_CALLS_LOG"
case "$*" in
  *"remote get-url origin"*) exit 1 ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$BIN_DIR/git"

  run bash "$BACKUP_SCRIPT"

  [ "$status" -eq 11 ]
  assert_output --partial 'DS-notes'
  assert_output --partial "no remote 'origin'"
}

@test "backup: DS-*/Pack-* push failed → exit 11, openssl не вызывается" {
  mkdir -p "$WORKSPACE_DIR/DS-notes/.git"
  export GIT_PUSH_EXIT=1

  run bash "$BACKUP_SCRIPT"

  [ "$status" -eq 11 ]
  assert_output --partial 'push failed'
  # openssl НЕ должен вызываться
  run grep 'aes-256-cbc' "$OPENSSL_CALLS_LOG"
  assert_failure
}

@test "backup: --help выводит usage и завершается успешно" {
  run bash "$BACKUP_SCRIPT" --help

  assert_success
  assert_output --partial 'Usage:'
  assert_output --partial 'BACKUP_GITHUB_REPO'
  assert_output --partial '--dry-run'
}

@test "backup: --dry-run — не вызывает openssl и gh" {
  run bash "$BACKUP_SCRIPT" --dry-run

  assert_success
  assert_output --partial 'DRY-RUN'

  # openssl и gh НЕ вызываются
  run grep 'openssl' "$OPENSSL_CALLS_LOG"
  assert_failure
  run grep 'release create' "$GH_CALLS_LOG"
  assert_failure
}

@test "backup: happy path — git commit+push, openssl enc, gh release upload" {
  mkdir -p "$WORKSPACE_DIR/DS-notes/.git"
  export GIT_DIFF_EXIT=1

  run bash "$BACKUP_SCRIPT"

  assert_success
  run grep 'add -u' "$GIT_CALLS_LOG";      assert_success
  run grep 'commit' "$GIT_CALLS_LOG";       assert_success
  run grep 'push origin' "$GIT_CALLS_LOG";  assert_success
  run grep 'aes-256-cbc' "$OPENSSL_CALLS_LOG"; assert_success
  run grep 'release create' "$GH_CALLS_LOG"; assert_success
  run grep 'release upload' "$GH_CALLS_LOG"; assert_success
}

@test "backup: нет DS-*/Pack-* репо — backup продолжается без sync" {
  run bash "$BACKUP_SCRIPT"

  assert_success
  assert_output --partial 'No DS-*/Pack-* repos found'
  run grep 'aes-256-cbc' "$OPENSSL_CALLS_LOG";  assert_success
  run grep 'release upload' "$GH_CALLS_LOG";     assert_success
}

@test "backup: --dry-run включает DS-*/Pack-* в список без push" {
  mkdir -p "$WORKSPACE_DIR/DS-notes/.git" "$WORKSPACE_DIR/PACK-test/.git"

  run bash "$BACKUP_SCRIPT" --dry-run

  assert_success
  assert_output --partial 'DS-notes'
  assert_output --partial 'PACK-test'
  run grep 'push origin' "$GIT_CALLS_LOG"; assert_failure
}

# ══════════════════════════════════════════════════════════════════════════════
# restore.sh tests
# ══════════════════════════════════════════════════════════════════════════════

@test "restore: --help выводит usage и завершается успешно" {
  run bash "$RESTORE_SCRIPT" --help

  assert_success
  assert_output --partial 'Usage:'
  assert_output --partial 'BACKUP_GITHUB_REPO'
  assert_output --partial '--tag'
}

@test "restore: meta.env отсутствует → exit с ошибкой" {
  local stage="$TEST_DIR/bad-stage"
  mkdir -p "$stage"
  echo "dummy" > "$stage/dummy.txt"
  local archive="$TEST_DIR/bad.tar.gz.enc"
  (cd "$stage" && /bin/tar -czf "$archive" .)
  export GH_DOWNLOAD_SOURCE="$archive"

  run bash "$RESTORE_SCRIPT" \
    --tag backup-2026-03-23-120000 \
    --workspace-dir "$WORKSPACE_DIR"

  assert_failure
  assert_output --partial 'meta.env'
}

@test "restore: openssl ошибка расшифровки → exit с ошибкой" {
  _build_backup_archive "$WORKSPACE_DIR"
  export OPENSSL_EXIT_CODE=1

  run bash "$RESTORE_SCRIPT" \
    --tag backup-2026-03-23-120000 \
    --workspace-dir "$WORKSPACE_DIR"

  assert_failure
  assert_output --partial 'Decryption failed'
}

@test "restore: восстанавливает CLAUDE.md, settings.local.json, env, claude-projects" {
  _build_backup_archive "$WORKSPACE_DIR"
  local new_ws="$TEST_DIR/restored/IWE2"
  local slug="${new_ws//\//-}"

  run bash "$RESTORE_SCRIPT" \
    --tag backup-2026-03-23-120000 \
    --workspace-dir "$new_ws"

  assert_success
  assert_file_exist "$new_ws/CLAUDE.md"
  assert_file_exist "$new_ws/.claude/settings.local.json"
  assert_file_exist "$HOME_DIR/.IWE2/env"
  assert_dir_exist  "$HOME_DIR/.claude/projects/${slug}/memory"
}

@test "restore: ремаппит WORKSPACE_DIR в env файле при смене пути" {
  local orig_ws="$WORKSPACE_DIR"
  local new_ws="$TEST_DIR/new-machine/IWE2"
  _build_backup_archive "$orig_ws"

  run bash "$RESTORE_SCRIPT" \
    --tag backup-2026-03-23-120000 \
    --workspace-dir "$new_ws"

  assert_success

  local restored_env="$HOME_DIR/.IWE2/env"
  assert_file_exist "$restored_env"
  run grep "WORKSPACE_DIR=${new_ws}" "$restored_env"; assert_success
  run grep "WORKSPACE_DIR=${orig_ws}" "$restored_env"; assert_failure
}

@test "restore: repo-list пуст — git clone не вызывается" {
  _build_backup_archive "$WORKSPACE_DIR"

  # Перепаковать архив с пустым repo-list.txt
  local stage2="$TEST_DIR/empty-repo-stage"
  mkdir -p "$stage2"
  (cd "$stage2" && /bin/tar -xzf "$GH_DOWNLOAD_SOURCE" .)
  echo "" > "$stage2/repo-list.txt"
  local archive2="$TEST_DIR/empty-repos.tar.gz.enc"
  (cd "$stage2" && /bin/tar -czf "$archive2" .)
  export GH_DOWNLOAD_SOURCE="$archive2"

  run bash "$RESTORE_SCRIPT" \
    --tag backup-2026-03-23-120000 \
    --workspace-dir "$WORKSPACE_DIR"

  assert_success
  run grep 'clone' "$GIT_CALLS_LOG"; assert_failure
}

@test "restore: существующий репо — git pull вместо clone" {
  _build_backup_archive "$WORKSPACE_DIR"
  mkdir -p "$WORKSPACE_DIR/DS-notes/.git"

  run bash "$RESTORE_SCRIPT" \
    --tag backup-2026-03-23-120000 \
    --workspace-dir "$WORKSPACE_DIR"

  assert_success
  run grep 'pull --rebase' "$GIT_CALLS_LOG"; assert_success
  run grep 'clone' "$GIT_CALLS_LOG";         assert_failure
}

# ══════════════════════════════════════════════════════════════════════════════
# install.sh tests
# ══════════════════════════════════════════════════════════════════════════════

@test "install: делает backup.sh и restore.sh исполняемыми" {
  chmod -x "$BACKUP_SCRIPT" "$RESTORE_SCRIPT"

  run bash "$INSTALL_SCRIPT"

  assert_success
  [ -x "$BACKUP_SCRIPT" ]
  [ -x "$RESTORE_SCRIPT" ]
}

@test "install: выводит инструкции по настройке" {
  run bash "$INSTALL_SCRIPT"

  assert_success
  assert_output --partial 'BACKUP_GITHUB_REPO'
  assert_output --partial 'gh auth login'
  assert_output --partial 'backup.sh'
}
