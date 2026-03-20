#!/usr/bin/env bats
# Тесты для setup.sh
#
# Покрытие: синтаксис, CLI-флаги, валидация template dir, prerequisites,
#           env-файл (включая injection safety), подстановка плейсхолдеров,
#           memory, roles, DS-strategy, dry-run, data policy skip
#
# Подход: subprocess с подменой зависимостей через PATH и HOME isolation.
# Все тесты запускают реальный setup.sh — без heredoc-копий функций.

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'
load 'test_helper/helpers'

ORIG_SCRIPT="${BATS_TEST_DIRNAME}/../setup.sh"

setup() {
  TEST_DIR="$BATS_TEST_TMPDIR"

  # Isolate HOME — prevent writes to real ~/.claude/, ~/.<ws>/, etc.
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME"

  # Git identity for DS-strategy commits (no git config dependency)
  export GIT_AUTHOR_NAME="Test"
  export GIT_AUTHOR_EMAIL="test@test.com"
  export GIT_COMMITTER_NAME="Test"
  export GIT_COMMITTER_EMAIL="test@test.com"

  # Template dir with placeholder files
  TEMPLATE_DIR="$TEST_DIR/template"
  make_template_dir "$TEMPLATE_DIR"
  cp "$ORIG_SCRIPT" "$TEMPLATE_DIR/setup.sh"
  SCRIPT="$TEMPLATE_DIR/setup.sh"

  # Mock external commands (gh, claude, node, npm; git passes through)
  setup_mocks "$TEST_DIR/bin"

  # Default workspace path
  WORKSPACE="$TEST_DIR/workspace"
}

# ── Helpers ───────────────────────────────────────────

# Run setup.sh --core with piped stdin answers
# Prompts: GITHUB_USER, EXOCORTEX_REPO, WORKSPACE_DIR (3 reads)
_run_core() {
  local ws="${1:-$WORKSPACE}"
  local user="${2:-testuser}"
  local repo="${3:-$(basename "$TEMPLATE_DIR")}"
  printf '%s\n%s\n%s\n' "$user" "$repo" "$ws" \
    | bash "$SCRIPT" --core
}

# Run setup.sh full mode with piped stdin answers
# Prompts: GITHUB_USER, EXOCORTEX_REPO, WORKSPACE_DIR,
#          CLAUDE_PATH, TIMEZONE_HOUR, TIMEZONE_DESC (6 reads)
# Data policy skipped (BATS_TEST_TMPDIR is set)
_run_full() {
  local ws="${1:-$WORKSPACE}"
  local user="${2:-testuser}"
  local repo="${3:-$(basename "$TEMPLATE_DIR")}"
  printf '%s\n%s\n%s\n%s\n%s\n%s\n' \
    "$user" "$repo" "$ws" \
    "/tmp/mock/claude" "4" "4:00 UTC" \
    | bash "$SCRIPT"
}

# ── 1. Syntax ─────────────────────────────────────────

@test "bash -n: setup.sh имеет валидный синтаксис" {
  run bash -n "$ORIG_SCRIPT"
  assert_success
}

# ── 2. CLI flags ──────────────────────────────────────

@test "--version: выводит версию и завершается с 0" {
  run bash "$SCRIPT" --version
  assert_success
  assert_output --partial "exocortex-setup v"
}

@test "--help: показывает справку со всеми опциями" {
  run bash "$SCRIPT" --help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "--core"
  assert_output --partial "--dry-run"
  assert_output --partial "--version"
}

@test "-h: алиас для --help" {
  run bash "$SCRIPT" -h
  assert_success
  assert_output --partial "Usage:"
}

# ── 3. Template dir validation ────────────────────────

@test "ошибка если CLAUDE.md отсутствует" {
  rm "$TEMPLATE_DIR/CLAUDE.md"
  run _run_core
  assert_failure
  assert_output --partial "ERROR"
  assert_output --partial "must be run from the root"
}

@test "ошибка если memory/ отсутствует" {
  rm -rf "$TEMPLATE_DIR/memory"
  run _run_core
  assert_failure
  assert_output --partial "ERROR"
}

# ── 4. Prerequisites ─────────────────────────────────

@test "--core: успех при наличии только git" {
  run _run_core
  assert_success
}

@test "--core: не проверяет gh, node, npm, claude" {
  rm -f "$TEST_DIR/bin/gh" "$TEST_DIR/bin/node" \
    "$TEST_DIR/bin/npm" "$TEST_DIR/bin/claude"
  run _run_core
  assert_success
  refute_output --partial "✗"
}

@test "full: проверяет наличие gh, node, npm, claude" {
  run _run_full
  assert_success
  assert_output --partial "GitHub CLI"
  assert_output --partial "Node.js"
  assert_output --partial "Claude Code"
}

@test "--core: баннер отображает режим core" {
  run _run_core
  assert_success
  assert_output --partial "(core)"
}

# ── 5. Dry-run ────────────────────────────────────────

@test "--dry-run --core: перечисляет все плейсхолдеры" {
  run bash "$SCRIPT" --dry-run --core <<'INPUT'
myuser
DS-test
/tmp/ws
INPUT
  assert_success
  assert_output --partial "{{GITHUB_USER}}"
  assert_output --partial "{{WORKSPACE_DIR}}"
  assert_output --partial "{{EXOCORTEX_REPO}}"
}

@test "--dry-run: не изменяет файлы шаблона" {
  bash "$SCRIPT" --dry-run --core <<'INPUT'
myuser
DS-test
/tmp/ws
INPUT
  # Плейсхолдеры должны остаться на месте
  run grep "{{WORKSPACE_DIR}}" "$TEMPLATE_DIR/memory/test.md"
  assert_success
}

@test "--dry-run: помечает каждый шаг [DRY RUN]" {
  run bash "$SCRIPT" --dry-run --core <<'INPUT'
myuser
DS-test
/tmp/ws
INPUT
  assert_output --partial "[DRY RUN]"
}

# ── 6. Env file ──────────────────────────────────────

@test "env-файл: создаётся в HOME/.<workspace-basename>/env" {
  _run_core "$WORKSPACE" "envuser"
  local ws_base
  ws_base="$(basename "$WORKSPACE")"
  assert_file_exist "$HOME/.$ws_base/env"
}

@test "env-файл: содержит все конфигурационные переменные" {
  _run_core "$WORKSPACE" "fulluser"
  local ws_base env_file
  ws_base="$(basename "$WORKSPACE")"
  env_file="$HOME/.$ws_base/env"
  run cat "$env_file"
  assert_output --partial "GITHUB_USER="
  assert_output --partial "EXOCORTEX_REPO="
  assert_output --partial "WORKSPACE_DIR="
  assert_output --partial "CLAUDE_PATH="
  assert_output --partial "TIMEZONE_HOUR="
  assert_output --partial "HOME_DIR="
  assert_output --partial "CLAUDE_PROJECT_SLUG="
}

@test "env-файл: права 600" {
  _run_core "$WORKSPACE" "permuser"
  local ws_base
  ws_base="$(basename "$WORKSPACE")"
  run stat -c "%a" "$HOME/.$ws_base/env"
  assert_output "600"
}

@test "env-файл: printf %q предотвращает injection при source" {
  # Передаём значение с командной подстановкой
  _run_core "$WORKSPACE" 'user$(whoami)'
  local ws_base env_file
  ws_base="$(basename "$WORKSPACE")"
  env_file="$HOME/.$ws_base/env"
  # Source env и проверить: значение — литерал, $(whoami) не раскрылась
  run bash -c "source \"$env_file\" && printf '%s' \"\$GITHUB_USER\""
  assert_output 'user$(whoami)'
}

# ── 7. Placeholder substitution ──────────────────────

@test "плейсхолдеры: заменяются в .md файлах" {
  _run_core "$WORKSPACE" "mduser"
  # {{WORKSPACE_DIR}} должен исчезнуть
  run grep "{{WORKSPACE_DIR}}" "$TEMPLATE_DIR/memory/test.md"
  assert_failure
  # Реальное значение должно присутствовать
  run grep "$WORKSPACE" "$TEMPLATE_DIR/memory/test.md"
  assert_success
}

@test "плейсхолдеры: заменяются в .yaml файлах" {
  _run_core "$WORKSPACE" "yamluser"
  run grep "{{WORKSPACE_DIR}}" "$TEMPLATE_DIR/test.yaml"
  assert_failure
  run grep "$WORKSPACE" "$TEMPLATE_DIR/test.yaml"
  assert_success
}

@test "плейсхолдеры: .sh файлы не затрагиваются" {
  printf '#!/bin/bash\necho "{{WORKSPACE_DIR}}"\n' \
    > "$TEMPLATE_DIR/test-script.sh"
  _run_core "$WORKSPACE"
  # Плейсхолдер в .sh должен остаться — скрипт не обрабатывает .sh файлы
  run grep "{{WORKSPACE_DIR}}" "$TEMPLATE_DIR/test-script.sh"
  assert_success
}

@test "плейсхолдеры: корректно обрабатывают имена файлов с пробелами" {
  echo "{{GITHUB_USER}}" > "$TEMPLATE_DIR/memory/file with spaces.md"
  _run_core "$WORKSPACE" "spaceuser"
  run grep "spaceuser" "$TEMPLATE_DIR/memory/file with spaces.md"
  assert_success
}

# ── 8. CLAUDE.md ──────────────────────────────────────

@test "CLAUDE.md: копируется в workspace" {
  _run_core "$WORKSPACE"
  assert_file_exist "$WORKSPACE/CLAUDE.md"
}

# ── 9. Memory ────────────────────────────────────────

@test "memory: файлы копируются в Claude projects dir" {
  _run_core "$WORKSPACE" "memuser"
  local slug mem_dir
  slug="$(echo "$WORKSPACE" | tr '/' '-')"
  mem_dir="$HOME/.claude/projects/$slug/memory"
  assert_file_exist "$mem_dir/MEMORY.md"
  assert_file_exist "$mem_dir/test.md"
}

@test "memory: symlink создаётся в workspace" {
  _run_core "$WORKSPACE" "symuser"
  assert_link_exist "$WORKSPACE/memory"
}

@test "memory: существующий путь не перезаписывается" {
  mkdir -p "$WORKSPACE/memory"
  echo "existing" > "$WORKSPACE/memory/keep.md"
  run _run_core "$WORKSPACE" "keepuser"
  assert_success
  assert_output --partial "WARN"
  assert_output --partial "already exists"
  # Оригинальный контент сохранён
  run cat "$WORKSPACE/memory/keep.md"
  assert_output "existing"
}

# ── 10. Roles ─────────────────────────────────────────

@test "roles: auto-install выполняет install.sh" {
  make_auto_role "$TEMPLATE_DIR" "testrole"
  run _run_full "$WORKSPACE" "roleuser"
  assert_success
  assert_output --partial "testrole installed"
}

@test "roles: manual — перечисляется, но не устанавливается" {
  make_manual_role "$TEMPLATE_DIR" "manrole" "Manual Role"
  run _run_full "$WORKSPACE" "manuser"
  assert_success
  assert_output --partial "Manual Role"
  assert_output --partial "install later"
  refute_output --partial "manrole installed"
}

@test "roles: предупреждение при отсутствии install.sh у auto-роли" {
  make_auto_role "$TEMPLATE_DIR" "broken"
  rm "$TEMPLATE_DIR/roles/broken/install.sh"
  run _run_full "$WORKSPACE" "brkuser"
  assert_success
  assert_output --partial "WARN"
  assert_output --partial "install.sh not found"
}

@test "roles: пропускаются в --core режиме" {
  make_auto_role "$TEMPLATE_DIR" "skipme"
  run _run_core "$WORKSPACE"
  assert_success
  assert_output --partial "пропущена (--core)"
  refute_output --partial "skipme installed"
}

# ── 11. DS-strategy ──────────────────────────────────

@test "DS-strategy: создаётся из seed с git init" {
  make_seed_strategy "$TEMPLATE_DIR"
  _run_core "$WORKSPACE" "seeduser"
  assert_dir_exist "$WORKSPACE/DS-strategy"
  assert_dir_exist "$WORKSPACE/DS-strategy/.git"
  assert_file_exist "$WORKSPACE/DS-strategy/CLAUDE.md"
}

@test "DS-strategy: пропускается если .git уже существует" {
  mkdir -p "$WORKSPACE/DS-strategy/.git"
  run _run_core "$WORKSPACE"
  assert_success
  assert_output --partial "already exists"
}

@test "DS-strategy: fallback-структура при отсутствии seed/" {
  _run_core "$WORKSPACE" "fbuser"
  assert_dir_exist "$WORKSPACE/DS-strategy"
  assert_dir_exist "$WORKSPACE/DS-strategy/inbox"
  assert_dir_exist "$WORKSPACE/DS-strategy/docs"
}

# ── 12. Repo rename ──────────────────────────────────

@test "rename: не переименовывает если имя совпадает с basename" {
  run _run_core "$WORKSPACE" "norenuser" "$(basename "$TEMPLATE_DIR")"
  assert_success
  assert_output --partial "unchanged"
}

@test "rename: пропускается если целевая директория существует" {
  local target_name="DS-existing"
  local target_dir
  target_dir="$(dirname "$TEMPLATE_DIR")/$target_name"
  mkdir -p "$target_dir"
  run _run_core "$WORKSPACE" "existuser" "$target_name"
  assert_success
  assert_output --partial "WARN"
  assert_output --partial "already exists"
}

# ── 13. Data policy ──────────────────────────────────

@test "data policy: пропускается в тестовом окружении (BATS_TEST_TMPDIR)" {
  # BATS_TEST_TMPDIR всегда установлен в bats — data policy block пропускается
  run _run_core "$WORKSPACE"
  assert_success
  refute_output --partial "Data Policy"
}

# ── 14. Completion ────────────────────────────────────

@test "завершение: выводит Setup Complete и инструкции" {
  run _run_core "$WORKSPACE"
  assert_success
  assert_output --partial "Setup Complete"
  assert_output --partial "Verify installation"
}
