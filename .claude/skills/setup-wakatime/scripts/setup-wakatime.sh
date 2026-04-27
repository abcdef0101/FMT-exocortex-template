#!/usr/bin/env bash
# setup-wakatime.sh — единый скрипт настройки WakaTime для Claude Code и VS Code.
# Вызывается из SKILL.md по подкомандам. Каждая подкоманда идемпотентна и атомарна.
#
# Состояние: WORKSPACE_DIR хранится в $STATE_FILE, переживает между вызовами.
# Корень репо: вычисляется от $CLAUDE_SKILL_DIR (или от пути скрипта если переменной нет).

set -euo pipefail

# === Пути ===
SKILL_DIR="${CLAUDE_SKILL_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="$(cd "$SKILL_DIR/../../.." && pwd)"
STATE_FILE="${TMPDIR:-/tmp}/wakatime-setup-state.env"

# === Утилиты ===
ok()   { echo "✓ $*"; }
fail() { echo "✗ FAIL: $*" >&2; exit 1; }

load_state() {
  [ -f "$STATE_FILE" ] && . "$STATE_FILE" || true
}

save_state() {
  umask 077
  printf 'WORKSPACE_DIR=%q\n' "$WORKSPACE_DIR" > "$STATE_FILE"
}

require_workspace() {
  load_state
  [ -n "${WORKSPACE_DIR:-}" ] && [ -d "$WORKSPACE_DIR" ] \
    || fail "WORKSPACE_DIR не установлен. Сначала запусти подкоманду 'workspace'."
}

# === Подкоманды ===

cmd_preflight() {
  for c in jq curl bash; do
    command -v "$c" >/dev/null 2>&1 \
      || fail "Требуется $c. Установи: brew install $c (macOS) или apt install $c (Linux)."
  done
  [ -f "$REPO_ROOT/.claude/hooks/wakatime-heartbeat.sh" ] \
    || fail "Хук-скрипт не найден: $REPO_ROOT/.claude/hooks/wakatime-heartbeat.sh"
  ok "preflight: jq, curl, bash, hook-script на месте"
}

cmd_cli() {
  if ~/.wakatime/wakatime-cli --version >/dev/null 2>&1; then
    ok "wakatime-cli уже установлен ($(~/.wakatime/wakatime-cli --version))"
    return
  fi

  mkdir -p ~/.wakatime

  local bin=""

  if command -v brew >/dev/null 2>&1; then
    brew install wakatime-cli
    # Свежий brew install — PATH может быть не обновлён в текущем shell.
    # Сначала пробуем brew --prefix (надёжный путь к бинарю), потом PATH.
    local brew_prefix
    if brew_prefix=$(brew --prefix wakatime-cli 2>/dev/null); then
      bin="$brew_prefix/bin/wakatime-cli"
    fi
    if [ ! -x "$bin" ]; then
      hash -r
      bin=$(command -v wakatime-cli || true)
    fi
    [ -n "$bin" ] && [ -x "$bin" ] \
      || fail "brew install прошёл, но wakatime-cli не найден (ни через brew --prefix, ни в PATH)"
  elif command -v pip3 >/dev/null 2>&1 \
       || command -v pip  >/dev/null 2>&1 \
       || command -v python3 >/dev/null 2>&1; then
    # Linux/любой Unix: пробуем pip3 → pip → python3 -m pip
    local pip_cmd
    if   command -v pip3   >/dev/null 2>&1; then pip_cmd="pip3 install --user wakatime"
    elif command -v pip    >/dev/null 2>&1; then pip_cmd="pip  install --user wakatime"
    else                                         pip_cmd="python3 -m pip install --user wakatime"
    fi
    eval "$pip_cmd"
    hash -r
    bin=$(command -v wakatime || true)
    # pip --user ставит бинарь в ~/.local/bin (не всегда в PATH)
    [ -n "$bin" ] || { [ -x "$HOME/.local/bin/wakatime" ] && bin="$HOME/.local/bin/wakatime"; }
    [ -n "$bin" ] && [ -x "$bin" ] \
      || fail "pip install прошёл, но wakatime не найден (PATH или ~/.local/bin)"
  else
    fail "Не найден ни brew, ни pip3/pip/python3. Скачай бинарь вручную: https://github.com/wakatime/wakatime-cli/releases"
  fi

  ln -sf "$bin" ~/.wakatime/wakatime-cli

  ~/.wakatime/wakatime-cli --version >/dev/null 2>&1 \
    || fail "Установка не удалась: ~/.wakatime/wakatime-cli не работает"
  ok "wakatime-cli установлен"
}

cmd_workspace() {
  local arg="${1:-current}"
  if [ -z "$arg" ] || [ "$arg" = "current" ]; then
    local current_link="$REPO_ROOT/workspaces/CURRENT_WORKSPACE"
    [ -L "$current_link" ] || fail "Симлинка $current_link не найдена. Используй iwe-workspace."
    WORKSPACE_DIR="$(cd "$current_link" && pwd -P)"
  else
    WORKSPACE_DIR="$REPO_ROOT/workspaces/$arg"
  fi

  [ -d "$WORKSPACE_DIR" ] || fail "Workspace не найден: $WORKSPACE_DIR"
  save_state
  ok "WORKSPACE_DIR=$WORKSPACE_DIR"
}

cmd_project() {
  require_workspace
  local name="${1:-}"
  [ -n "$name" ] || fail "usage: $0 project <имя>"

  # Идемпотентность: если файл уже содержит то же имя — пропустить
  if [ -f "$WORKSPACE_DIR/.wakatime-project" ] \
     && [ "$(cat "$WORKSPACE_DIR/.wakatime-project")" = "$name" ]; then
    ok "имя проекта уже задано: $name"
    return
  fi

  printf '%s\n' "$name" > "$WORKSPACE_DIR/.wakatime-project"
  ok "имя проекта записано: $name"
}

cmd_apikey() {
  require_workspace
  local key="${1:-}"
  [ -n "$key" ] || fail "usage: $0 apikey <ключ>"

  # Идемпотентность: если ключ уже валидный — пропустить
  if grep -q "^api_key = waka_" "$WORKSPACE_DIR/.wakatime.cfg" 2>/dev/null; then
    ok "API key уже установлен"
    return
  fi

  # Атомарная запись через tmp-файл
  local tmp="$WORKSPACE_DIR/.wakatime.cfg.tmp.$$"
  printf '[settings]\napi_key = %s\n' "$key" > "$tmp"
  mv "$tmp" "$WORKSPACE_DIR/.wakatime.cfg"
  ok "API key записан в $WORKSPACE_DIR/.wakatime.cfg"
}

cmd_hooks() {
  require_workspace
  local settings="$WORKSPACE_DIR/.claude/settings.json"

  mkdir -p "$WORKSPACE_DIR/.claude"
  [ -f "$settings" ] || echo '{}' > "$settings"

  # Идемпотентность через jq (точный поиск по командам хуков)
  if jq -e '.. | strings? | select(contains("wakatime-heartbeat"))' "$settings" \
       >/dev/null 2>&1; then
    ok "хуки wakatime уже настроены"
    return
  fi

  # Бэкап + атомарная подмена через jq
  cp "$settings" "$settings.bak" || fail "не могу создать бэкап $settings.bak"

  # Абсолютный путь к хуку — не зависит от CWD при запуске Claude Code
  local hook_path="$REPO_ROOT/.claude/hooks/wakatime-heartbeat.sh"

  if jq --arg hook "$hook_path" '
      .hooks //= {}
    | .hooks.UserPromptSubmit //= []
    | .hooks.PostToolUse //= []
    | .hooks.Stop //= []
    | .hooks.UserPromptSubmit += [{"hooks": [{"type": "command", "command": $hook}]}]
    | .hooks.PostToolUse     += [{"hooks": [{"type": "command", "command": $hook, "async": true}]}]
    | .hooks.Stop            += [{"hooks": [{"type": "command", "command": $hook, "async": true}]}]
  ' "$settings" > "$settings.new" 2>/dev/null; then
    mv "$settings.new" "$settings"
    rm -f "$settings.bak"
    ok "хуки добавлены в $settings"
  else
    rm -f "$settings.new"
    mv "$settings.bak" "$settings"
    fail "jq не справился, settings.json восстановлен из бэкапа"
  fi
}

cmd_symlinks() {
  require_workspace

  # ВНИМАНИЕ: симлинка ~/.wakatime.cfg хранит АБСОЛЮТНЫЙ путь к репо.
  # Если репо переместить — симлинка станет битой. Запусти 'symlinks' заново
  # после перемещения: предыдущая симлинка перезапишется (ln -sf).

  # 1. Симлинка .wakatime-project в корне репо → workspaces/CURRENT_WORKSPACE/.wakatime-project
  cd "$REPO_ROOT"
  local target1="workspaces/CURRENT_WORKSPACE/.wakatime-project"
  if [ "$(readlink ".wakatime-project" 2>/dev/null || true)" = "$target1" ]; then
    ok "симлинка .wakatime-project уже корректна"
  else
    ln -sf "$target1" ".wakatime-project"
    ok "создана .wakatime-project → $target1"
  fi

  # 2. Симлинка .wakatime.cfg в корне репо → workspaces/CURRENT_WORKSPACE/.wakatime.cfg
  local target2="workspaces/CURRENT_WORKSPACE/.wakatime.cfg"
  if [ "$(readlink ".wakatime.cfg" 2>/dev/null || true)" = "$target2" ]; then
    ok "симлинка .wakatime.cfg уже корректна"
  else
    ln -sf "$target2" ".wakatime.cfg"
    ok "создана .wakatime.cfg → $target2"
  fi

  # 3. Глобальная симлинка ~/.wakatime.cfg → <repo>/.wakatime.cfg
  local target3="$REPO_ROOT/.wakatime.cfg"
  if [ "$(readlink "$HOME/.wakatime.cfg" 2>/dev/null || true)" = "$target3" ]; then
    ok "симлинка ~/.wakatime.cfg уже корректна"
  elif [ -e "$HOME/.wakatime.cfg" ] && [ ! -L "$HOME/.wakatime.cfg" ]; then
    fail "$HOME/.wakatime.cfg существует как обычный файл — переименуй или удали и повтори"
  else
    ln -sf "$target3" "$HOME/.wakatime.cfg"
    ok "создана ~/.wakatime.cfg → $target3"
  fi
}

cmd_desktop() {
  if [ "$(uname -s)" != "Darwin" ]; then
    ok "Desktop App пропущен (не macOS)"
    return
  fi
  command -v brew >/dev/null 2>&1 || fail "brew нужен для установки Desktop App"

  if brew list --cask wakatime >/dev/null 2>&1; then
    ok "WakaTime Desktop уже установлен"
  else
    brew install --cask wakatime
    ok "WakaTime Desktop установлен"
  fi

  open -a WakaTime 2>/dev/null || true
  echo "ℹ Разреши Accessibility: System Settings → Privacy & Security → Accessibility"
}

cmd_test() {
  require_workspace
  local hook="$REPO_ROOT/.claude/hooks/wakatime-heartbeat.sh"
  [ -f "$hook" ] || fail "хук-скрипт не найден: $hook"

  # Извлекаем API ключ (нужен для обеих проверок)
  local key
  key=$(awk -F= '/^api_key/ {gsub(/[ \t]/, "", $2); print $2; exit}' \
    "$WORKSPACE_DIR/.wakatime.cfg")
  [ -n "$key" ] || fail "API key не найден в $WORKSPACE_DIR/.wakatime.cfg"

  # --- 7.1: валидация API ключа ---
  # HTTP Basic — ключ в заголовке, не в URL (не светится в логах/истории)
  local response http_code body username
  response=$(curl -sS -w "\n%{http_code}" -u "$key:" \
    "https://wakatime.com/api/v1/users/current" 2>&1) \
    || fail "curl /users/current не отработал: $response"
  http_code=$(printf '%s\n' "$response" | tail -n1)
  body=$(printf '%s\n' "$response" | sed '$d')
  [ "$http_code" = "200" ] \
    || fail "API /users/current вернул HTTP $http_code. Тело: $body"
  username=$(printf '%s' "$body" | jq -r '.data.username // "unknown"')
  ok "API ключ валиден: пользователь $username"

  # --- 7.2: end-to-end доставка heartbeat ---
  # Фиксируем момент ДО отправки — потом ищем heartbeats с time >= t0
  local t0 payload
  t0=$(date +%s)

  payload=$(jq -n --arg cwd "$REPO_ROOT" \
    '{cwd: $cwd, hook_event_name: "UserPromptSubmit", prompt: "test"}')
  echo "$payload" | bash "$hook" \
    || fail "хук-скрипт упал (exit $?)"

  # wakatime-cli отправляет heartbeat в фоне — даём время долететь
  sleep 3

  # Запрашиваем heartbeats за сегодня
  local hb_response hb_code hb_body found
  hb_response=$(curl -sS -w "\n%{http_code}" -u "$key:" \
    "https://wakatime.com/api/v1/users/current/heartbeats?date=$(date +%Y-%m-%d)" 2>&1) \
    || fail "curl /heartbeats не отработал: $hb_response"
  hb_code=$(printf '%s\n' "$hb_response" | tail -n1)
  hb_body=$(printf '%s\n' "$hb_response" | sed '$d')
  [ "$hb_code" = "200" ] \
    || fail "API /heartbeats вернул HTTP $hb_code. Тело: $hb_body"

  # Считаем сколько heartbeats пришло после t0 (с учётом float-timestamp)
  found=$(printf '%s' "$hb_body" \
    | jq --argjson t0 "$t0" '[.data[]? | select(.time >= $t0)] | length' \
       2>/dev/null || echo "0")

  if [ "${found:-0}" -gt 0 ]; then
    ok "heartbeat доставлен в WakaTime ($found новых записей с момента теста)"
  else
    fail "heartbeat отправлен, но не найден в API после 3с. Проверь: системные часы, доступ wakatime-cli в интернет, права API ключа на запись."
  fi
}

cmd_summary() {
  require_workspace

  status() {
    if eval "$1" >/dev/null 2>&1; then echo "✅"; else echo "❌"; fi
  }

  cd "$REPO_ROOT"

  printf '\n'
  printf '| Компонент | Статус |\n'
  printf '|-----------|--------|\n'
  printf '| wakatime-cli | %s |\n' \
    "$(status '~/.wakatime/wakatime-cli --version')"
  printf '| .wakatime-project | %s |\n' \
    "$(status "[ -s '$WORKSPACE_DIR/.wakatime-project' ]")"
  printf '| API key | %s |\n' \
    "$(status "grep -q '^api_key = waka_' '$WORKSPACE_DIR/.wakatime.cfg'")"
  printf '| Хуки в settings.json | %s |\n' \
    "$(status "jq -e '.. | strings? | select(contains(\"wakatime-heartbeat\"))' '$WORKSPACE_DIR/.claude/settings.json'")"
  printf '| Симлинка .wakatime.cfg в репо | %s |\n' \
    "$(status "[ -L .wakatime.cfg ]")"
  printf '| Глобальная ~/.wakatime.cfg | %s |\n' \
    "$(status "[ -L $HOME/.wakatime.cfg ]")"
  if [ "$(uname -s)" = "Darwin" ]; then
    printf '| WakaTime Desktop App | %s |\n' \
      "$(status "brew list --cask wakatime")"
  fi
  printf '\n'
  printf 'Дашборд: https://wakatime.com/dashboard\n'
}

# === Диспатчер ===

case "${1:-help}" in
  preflight) shift; cmd_preflight "$@" ;;
  cli)       shift; cmd_cli "$@" ;;
  workspace) shift; cmd_workspace "${1:-current}" ;;
  project)   shift; cmd_project "$@" ;;
  apikey)    shift; cmd_apikey "$@" ;;
  hooks)     shift; cmd_hooks "$@" ;;
  symlinks)  shift; cmd_symlinks "$@" ;;
  desktop)   shift; cmd_desktop "$@" ;;
  test)      shift; cmd_test "$@" ;;
  summary)   shift; cmd_summary "$@" ;;
  help|--help|-h)
    cat <<EOF
Usage: $0 <command> [args]

Commands:
  preflight              Проверить jq, curl, bash, hook-script
  cli                    Установить wakatime-cli (brew → pip3 → pip → python3 -m pip)
  workspace [<имя>]      Выбрать workspace (по умолчанию CURRENT_WORKSPACE)
  project <имя>          Записать имя проекта в .wakatime-project
  apikey <ключ>          Записать API ключ в .wakatime.cfg
  hooks                  Добавить хуки в settings.json (атомарно через jq)
  symlinks               Создать 3 симлинки идемпотентно
  desktop                Установить WakaTime Desktop App (только macOS)
  test                   Тест heartbeat + API ключа
  summary                Финальная таблица состояния

State: $STATE_FILE
EOF
    ;;
  *)
    fail "Unknown command: $1. Run '$0 help' for usage."
    ;;
esac
