---
name: setup-wakatime
description: Настройка WakaTime time-tracking для Claude Code и VS Code
user_invocable: true
allowed-tools: Bash(bash "${CLAUDE_SKILL_DIR}/scripts/setup-wakatime.sh" *)
---

# Setup WakaTime Time Tracking

Автоматическая настройка WakaTime для отслеживания рабочего времени.

**Безопасно запускать повторно** — каждая подкоманда проверяет состояние и пропускается если уже сделано.

## Что устанавливается

1. **wakatime-cli** — CLI для отправки heartbeat'ов
2. **`.wakatime-project`** — имя проекта в WakaTime для выбранного workspace
3. **Хуки Claude Code** — автоматический трекинг (категория "AI Coding")
4. **WakaTime Desktop App** (опционально, macOS) — трекинг фокуса окна

## Архитектура

Вся техническая логика — в `scripts/setup-wakatime.sh`. SKILL.md только:
1. Спрашивает пользователя что нужно
2. Вызывает соответствующую подкоманду скрипта
3. Парсит вывод: `✓` — успех, `✗ FAIL: <причина>` — стоп, сообщи пользователю причину

Состояние `WORKSPACE_DIR` сохраняется в `/tmp/wakatime-setup-state.env` между вызовами.

## Инструкция для Claude

### Шаг 1: Pre-flight + установка wakatime-cli

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/setup-wakatime.sh" preflight
bash "${CLAUDE_SKILL_DIR}/scripts/setup-wakatime.sh" cli
```

Если `preflight` упал на `jq`/`curl` — попроси пользователя установить и вернуться.

### Шаг 2: Workspace + имя проекта

Покажи варианты:
```bash
ls workspaces/
readlink workspaces/CURRENT_WORKSPACE 2>/dev/null
```

Спроси: «Для какого workspace настраиваем? Enter — текущий (CURRENT_WORKSPACE), или введи имя из списка».

Передай ответ в скрипт (Enter → `current`):
```bash
bash "${CLAUDE_SKILL_DIR}/scripts/setup-wakatime.sh" workspace "<имя или current>"
```

Проверь существующее имя проекта:
```bash
cat "$(. /tmp/wakatime-setup-state.env && echo "$WORKSPACE_DIR/.wakatime-project")" 2>/dev/null
```

- Если файл существует и непустой — спроси: «Оставить `<текущее>` или изменить?»
- Если пустой/нет — спроси: «Как назвать workspace в WakaTime? (например: IWE-main)»

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/setup-wakatime.sh" project "<имя проекта>"
```

### Шаг 3: API ключ

Спроси: «WakaTime API-ключ? Получи на https://wakatime.com/settings/api-key (нужна регистрация). Вставь ключ.»

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/setup-wakatime.sh" apikey "<ключ>"
```

Если скрипт ответил `API key уже установлен` — отлично, шаг пропущен.

### Шаг 4: Хуки в settings.json

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/setup-wakatime.sh" hooks
```

Атомарно: бэкап → jq → подмена. При сбое jq бэкап восстанавливается автоматически.

### Шаг 5: Симлинки

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/setup-wakatime.sh" symlinks
```

Создаёт три симлинки идемпотентно:
- `<repo>/.wakatime-project` → `workspaces/CURRENT_WORKSPACE/.wakatime-project`
- `<repo>/.wakatime.cfg` → `workspaces/CURRENT_WORKSPACE/.wakatime.cfg`
- `~/.wakatime.cfg` → `<repo>/.wakatime.cfg`

### Шаг 6: WakaTime Desktop App (только macOS)

На macOS спроси: «Установить WakaTime Desktop App? Он трекает время фокуса окна. Требует Accessibility-разрешение.»

Если да:
```bash
bash "${CLAUDE_SKILL_DIR}/scripts/setup-wakatime.sh" desktop
```

После установки скажи: «Разреши Accessibility в System Settings → Privacy & Security → Accessibility.»

### Шаг 7: Тесты

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/setup-wakatime.sh" test
```

Тест 7.1 — heartbeat: посылает тестовый heartbeat через хук-скрипт.
Тест 7.2 — API ключ: запрашивает `users/current` у WakaTime API, проверяет HTTP 200.

Если тест провален — выведи причину пользователю и предложи действия:
- `heartbeat` падает → проверь `~/.wakatime.cfg` симлинку (Шаг 5)
- `API вернул HTTP 401` → ключ неверный, обнови (Шаг 3)
- `API вернул HTTP 5xx` → проблема на стороне WakaTime, попробуй позже

### Шаг 8: Итог

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/setup-wakatime.sh" summary
```

Скажи пользователю: «Дашборд: https://wakatime.com/dashboard. Данные появятся через 5–15 минут. Хуки активируются при следующем запуске Claude Code.»

## Обработка ошибок

Скрипт всегда выходит с явным статусом:
- `exit 0` + строка `✓ <что сделано>` — успех, идём дальше
- `exit 1` + строка `✗ FAIL: <причина>` — стоп, разбери причину и помоги пользователю

При сбое не перезапускай скилл целиком — повтори только проблемный шаг (всё идемпотентно).
