#!/usr/bin/env bash
# setup-wakatime.sh — единый скрипт настройки WakaTime для Claude Code и VS Code.
# Вызывается из SKILL.md по подкомандам. Каждая подкоманда идемпотентна и атомарна.
#
# Состояние: WORKSPACE_DIR хранится в $STATE_FILE, переживает между вызовами.
# Корень репо: вычисляется от $CLAUDE_SKILL_DIR (или от пути скрипта если переменной нет).

set -euo pipefail

# === Утилиты ===
ok()   { echo "✓ $*"; }
fail() { echo "✗ FAIL: $*" >&2; exit 1; }

# === Пути ===
# Bash <4.4 не пропускает ошибку из $() через assignment под set -e —
# поэтому проверяем результат явно после каждой подстановки.
SKILL_DIR="${CLAUDE_SKILL_DIR:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
[ -n "$SKILL_DIR" ] && [ -d "$SKILL_DIR" ] \
  || fail "не могу определить SKILL_DIR (CLAUDE_SKILL_DIR пуст, dirname \$0 не работает)"
REPO_ROOT="$(cd "$SKILL_DIR/../../.." 2>/dev/null && pwd)"
[ -n "$REPO_ROOT" ] && [ -d "$REPO_ROOT" ] \
  || fail "не могу определить REPO_ROOT от $SKILL_DIR"
STATE_FILE="${TMPDIR:-/tmp}/wakatime-setup-state.env"

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

# === Helpers для .wakatime.cfg (INI-формат) ===
# Атомарно читают/пишут одну пару key=value в [settings], сохраняя остальное.

cfg_get() {
  local key="$1"
  local cfg="$WORKSPACE_DIR/.wakatime.cfg"
  [ -f "$cfg" ] || return 0
  awk -F= -v key="$key" '
    $0 ~ "^[[:space:]]*"key"[[:space:]]*=" {
      gsub(/^[ \t]+|[ \t]+$/, "", $2)
      print $2
      exit
    }
  ' "$cfg"
}

cfg_set() {
  local key="$1"
  local value="$2"
  local cfg="$WORKSPACE_DIR/.wakatime.cfg"
  local tmp="$cfg.tmp.$$"

  if [ ! -f "$cfg" ]; then
    printf '[settings]\n%s = %s\n' "$key" "$value" > "$tmp"
    mv "$tmp" "$cfg"
    return
  fi

  # awk: при встрече [settings] вставляет key=value сразу после header,
  # пропускает старую строку с этим key, остальное копирует as-is.
  awk -v key="$key" -v value="$value" '
    BEGIN { written = 0 }
    /^\[settings\]/ {
      print
      print key " = " value
      written = 1
      next
    }
    $0 ~ "^[[:space:]]*"key"[[:space:]]*=" { next }
    { print }
    END {
      if (!written) {
        print "[settings]"
        print key " = " value
      }
    }
  ' "$cfg" > "$tmp"
  mv "$tmp" "$cfg"
}

cfg_unset() {
  local key="$1"
  local cfg="$WORKSPACE_DIR/.wakatime.cfg"
  [ -f "$cfg" ] || return 0
  local tmp="$cfg.tmp.$$"
  awk -v key="$key" '
    $0 ~ "^[[:space:]]*"key"[[:space:]]*=" { next }
    { print }
  ' "$cfg" > "$tmp"
  mv "$tmp" "$cfg"
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
  local current_link="$REPO_ROOT/workspaces/CURRENT_WORKSPACE"
  [ -L "$current_link" ] || fail "Симлинка $current_link не найдена. Используй iwe-workspace."

  WORKSPACE_DIR="$(cd "$current_link" && pwd -P)" \
    || fail "не могу разрешить симлинку $current_link"
  local current_name
  current_name=$(basename "$WORKSPACE_DIR")

  # Защита от path-traversal в имени
  case "$arg" in
    *..*|*/*) fail "недопустимое имя workspace: '$arg' (запрещены '..' и '/')" ;;
  esac

  # Skill настраивает то, на что указывают симлинки в репо — то есть CURRENT_WORKSPACE.
  # Настройка другого workspace создаст рассинхрон между .wakatime.cfg в выбранном
  # workspace и симлинкой ~/.wakatime.cfg → CURRENT_WORKSPACE → другой workspace.
  if [ "$arg" != "current" ] && [ "$arg" != "$current_name" ]; then
    fail "Выбран workspace '$arg', но CURRENT_WORKSPACE → '$current_name'. Симлинки завязаны на CURRENT_WORKSPACE — рассинхрон сломает heartbeat. Сначала переключись: iwe-workspace switch $arg"
  fi

  save_state
  ok "WORKSPACE_DIR=$WORKSPACE_DIR (CURRENT_WORKSPACE → $current_name)"
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

cmd_current_project() {
  # Печатает имя проекта из выбранного workspace (для использования в SKILL.md
  # как замена ручному парсингу state-файла). Не падает если файла нет.
  require_workspace
  cat "$WORKSPACE_DIR/.wakatime-project" 2>/dev/null || true
}

cmd_apikey() {
  require_workspace
  local key="${1:-}"
  [ -n "$key" ] || fail "usage: $0 apikey <ключ>"

  # Валидация формата: WakaTime cloud (waka_<uuid>) или bare UUID (wakapi.dev / self-hosted)
  case "$key" in
    waka_[0-9a-fA-F]*-[0-9a-fA-F]*-[0-9a-fA-F]*-[0-9a-fA-F]*-[0-9a-fA-F]*) : ;;
    [0-9a-fA-F]*-[0-9a-fA-F]*-[0-9a-fA-F]*-[0-9a-fA-F]*-[0-9a-fA-F]*)      : ;;
    *) fail "ключ не похож на UUID API key (ожидается waka_<uuid> для WakaTime cloud или <uuid> для wakapi/self-hosted): $key" ;;
  esac

  local current
  current=$(cfg_get "api_key")
  if [ "$current" = "$key" ]; then
    ok "API key не изменился (уже записан)"
    return
  fi

  cfg_set "api_key" "$key"

  if [ -n "$current" ]; then
    ok "API key обновлён в $WORKSPACE_DIR/.wakatime.cfg"
  else
    ok "API key записан в $WORKSPACE_DIR/.wakatime.cfg"
  fi
}

cmd_apiurl() {
  require_workspace
  local arg="${1:-}"

  # Сброс на дефолт WakaTime cloud (api.wakatime.com)
  if [ -z "$arg" ] || [ "$arg" = "default" ] || [ "$arg" = "wakatime" ]; then
    if [ -z "$(cfg_get api_url)" ]; then
      ok "api_url не задан (используется default api.wakatime.com)"
    else
      cfg_unset "api_url"
      ok "api_url сброшен → default api.wakatime.com"
    fi
    return
  fi

  # Шорткаты + валидация URL
  local url="$arg"
  case "$arg" in
    wakapi) url="https://wakapi.dev/api/compat/wakatime/v1" ;;
    https://*|http://*) : ;;
    *) fail "ожидается полный URL (https://...), 'wakapi' (для wakapi.dev), или 'default'/'wakatime' для сброса. Получено: $arg" ;;
  esac

  local current
  current=$(cfg_get "api_url")
  if [ "$current" = "$url" ]; then
    ok "api_url не изменился (уже $url)"
    return
  fi
  cfg_set "api_url" "$url"

  if [ -n "$current" ]; then
    ok "api_url обновлён: $url"
  else
    ok "api_url установлен: $url"
  fi
}

cmd_hooks() {
  require_workspace
  local settings="$WORKSPACE_DIR/.claude/settings.json"

  mkdir -p "$WORKSPACE_DIR/.claude"
  [ -f "$settings" ] || echo '{}' > "$settings"

  # Абсолютный путь к хуку — не зависит от CWD при запуске Claude Code
  local hook_path="$REPO_ROOT/.claude/hooks/wakatime-heartbeat.sh"

  # Идемпотентность по точному пути: если уже зарегистрирован с current $hook_path — выходим
  if jq -e --arg hook "$hook_path" \
       '.. | .command? // empty | select(. == $hook)' \
       "$settings" >/dev/null 2>&1; then
    ok "хуки wakatime уже настроены (точный путь)"
    return
  fi

  # Есть ли stale-хуки с wakatime-heartbeat по ДРУГОМУ пути (например после перемещения репо)?
  local has_stale="false"
  if jq -e '.. | .command? // empty | select(tostring | contains("wakatime-heartbeat"))' \
       "$settings" >/dev/null 2>&1; then
    has_stale="true"
  fi

  # Бэкап + атомарная подмена через jq.
  # Шаги: чистим stale wakatime-heartbeat записи (любые пути) → добавляем свежие с current $hook_path.
  cp "$settings" "$settings.bak" || fail "не могу создать бэкап $settings.bak"

  if jq --arg hook "$hook_path" '
      .hooks //= {}
    | .hooks.UserPromptSubmit //= []
    | .hooks.PostToolUse //= []
    | .hooks.Stop //= []
    | .hooks.UserPromptSubmit |= map(select((.hooks // []) | map(.command // "") | all(contains("wakatime-heartbeat") | not)))
    | .hooks.PostToolUse     |= map(select((.hooks // []) | map(.command // "") | all(contains("wakatime-heartbeat") | not)))
    | .hooks.Stop            |= map(select((.hooks // []) | map(.command // "") | all(contains("wakatime-heartbeat") | not)))
    | .hooks.UserPromptSubmit += [{"hooks": [{"type": "command", "command": $hook}]}]
    | .hooks.PostToolUse     += [{"hooks": [{"type": "command", "command": $hook, "async": true}]}]
    | .hooks.Stop            += [{"hooks": [{"type": "command", "command": $hook, "async": true}]}]
  ' "$settings" > "$settings.new" 2>/dev/null; then
    mv "$settings.new" "$settings"
    rm -f "$settings.bak"
    if [ "$has_stale" = "true" ]; then
      ok "хуки обновлены: stale-путь заменён на $hook_path"
    else
      ok "хуки добавлены в $settings"
    fi
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
  cd "$REPO_ROOT" || fail "cd $REPO_ROOT не отработал"
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

  # Извлекаем API ключ + URL backend'а (нужны для обеих проверок).
  # Если api_url не задан — используем default WakaTime cloud.
  local key api_url
  key=$(cfg_get "api_key")
  [ -n "$key" ] || fail "API key не найден в $WORKSPACE_DIR/.wakatime.cfg"
  api_url=$(cfg_get "api_url")
  : "${api_url:=https://api.wakatime.com/api/v1}"

  # --- 7.1: валидация API ключа ---
  # HTTP Basic — ключ в заголовке, не в URL (не светится в логах/истории)
  local response http_code body username
  response=$(curl -sS --connect-timeout 10 --max-time 30 \
      -w "\n%{http_code}" -u "$key:" \
      "$api_url/users/current" 2>&1) \
    || fail "curl $api_url/users/current не отработал: $response"
  http_code=$(printf '%s\n' "$response" | tail -n1)
  body=$(printf '%s\n' "$response" | sed '$d')
  [ "$http_code" = "200" ] \
    || fail "API $api_url/users/current вернул HTTP $http_code. Тело: $body"
  username=$(printf '%s' "$body" | jq -r '.data.username // "unknown"')
  ok "API ключ валиден: пользователь $username (backend: $api_url)"

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
  hb_response=$(curl -sS --connect-timeout 10 --max-time 30 \
      -w "\n%{http_code}" -u "$key:" \
      "$api_url/users/current/heartbeats?date=$(date +%Y-%m-%d)" 2>&1) \
    || fail "curl $api_url/heartbeats не отработал: $hb_response"
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

  # status <строгая_проверка> [мягкая_проверка]
  #   строгая ✓ → ✅ (полностью настроено)
  #   строгая ✗, мягкая ✓ → ⚠ (файл/симлинка есть, но содержимое не валидно)
  #   обе ✗ → ❌ (не настроено)
  status() {
    local strict="$1"
    local lenient="${2:-}"
    if eval "$strict" >/dev/null 2>&1; then
      echo "✅"
    elif [ -n "$lenient" ] && eval "$lenient" >/dev/null 2>&1; then
      echo "⚠"
    else
      echo "❌"
    fi
  }

  cd "$REPO_ROOT" || fail "cd $REPO_ROOT не отработал"

  local cfg="$WORKSPACE_DIR/.wakatime.cfg"
  local proj="$WORKSPACE_DIR/.wakatime-project"
  local settings="$WORKSPACE_DIR/.claude/settings.json"

  printf '\n'
  printf '| Компонент | Статус |\n'
  printf '|-----------|--------|\n'
  printf '| wakatime-cli | %s |\n' \
    "$(status '~/.wakatime/wakatime-cli --version')"
  printf '| .wakatime-project | %s |\n' \
    "$(status "[ -s '$proj' ]" "[ -f '$proj' ]")"
  printf '| API key | %s |\n' \
    "$(status "grep -qE '^[[:space:]]*api_key[[:space:]]*=[[:space:]]*[^[:space:]]+' '$cfg'" "[ -f '$cfg' ]")"
  local api_url
  api_url=$(cfg_get "api_url")
  printf '| Backend (api_url) | %s |\n' \
    "${api_url:-default (api.wakatime.com)}"
  printf '| Хуки в settings.json | %s |\n' \
    "$(status "jq -e '.. | strings? | select(contains(\"wakatime-heartbeat\"))' '$settings'" "[ -f '$settings' ]")"
  printf '| Симлинка .wakatime.cfg в репо | %s |\n' \
    "$(status "[ -L .wakatime.cfg ] && [ -e .wakatime.cfg ]" "[ -L .wakatime.cfg ]")"
  printf '| Глобальная ~/.wakatime.cfg | %s |\n' \
    "$(status "[ -L \"$HOME/.wakatime.cfg\" ] && [ -e \"$HOME/.wakatime.cfg\" ]" "[ -L \"$HOME/.wakatime.cfg\" ]")"
  if [ "$(uname -s)" = "Darwin" ]; then
    printf '| WakaTime Desktop App | %s |\n' \
      "$(status 'brew list --cask wakatime')"
  fi
  printf '\nЛегенда: ✅ — настроено, ⚠ — файл/симлинка есть но не валидно (битая, пустая), ❌ — не настроено\n'
  printf 'Дашборд: https://wakatime.com/dashboard\n'
}

# === Диспатчер ===

case "${1:-help}" in
  preflight) shift; cmd_preflight "$@" ;;
  cli)       shift; cmd_cli "$@" ;;
  workspace)       shift; cmd_workspace "${1:-current}" ;;
  project)         shift; cmd_project "$@" ;;
  current-project) shift; cmd_current_project "$@" ;;
  apikey)          shift; cmd_apikey "$@" ;;
  apiurl)          shift; cmd_apiurl "$@" ;;
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
  current-project        Вывести текущее имя проекта (для SKILL.md, без падения если нет)
  apikey <ключ>          Записать API ключ в .wakatime.cfg (валидация формата + force-update)
  apiurl <url|wakapi|default>  Установить api_url (для wakapi.dev / self-hosted; default — WakaTime cloud)
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
