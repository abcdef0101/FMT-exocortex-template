---
name: setup-wakatime
description: Настройка WakaTime time-tracking для Claude Code и VS Code
user_invocable: true
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

Передай ответ в скрипт (Enter или явное имя CURRENT_WORKSPACE → `current`):
```bash
bash "${CLAUDE_SKILL_DIR}/scripts/setup-wakatime.sh" workspace "<имя или current>"
```

Скрипт откажет с понятным сообщением если выбранный workspace ≠ CURRENT_WORKSPACE — это намеренная защита от рассинхрона симлинок.

Проверь существующее имя проекта:
```bash
bash "${CLAUDE_SKILL_DIR}/scripts/setup-wakatime.sh" current-project
```

- Если вывод непустой — спроси: «Оставить `<текущее>` или изменить?»
- Если пустой — спроси: «Как назвать workspace в WakaTime? (например: IWE-main)»

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/setup-wakatime.sh" project "<имя проекта>"
```

### Шаг 3: Backend + API ключ

**3.1 Выбор backend.** Спроси:
> «Какой WakaTime backend используешь?
> 1. **WakaTime Cloud** (https://wakatime.com) — основной, default
> 2. **wakapi.dev** (self-hosted-as-a-service, https://wakapi.dev)
> 3. **Свой self-hosted instance** — введи URL вида `https://my-wakapi.example.com/api/compat/wakatime/v1`
>
> Выбери 1, 2 или вставь URL.»

В зависимости от ответа:
```bash
# Вариант 1 (WakaTime Cloud):
bash "${CLAUDE_SKILL_DIR}/scripts/setup-wakatime.sh" apiurl default

# Вариант 2 (wakapi.dev):
bash "${CLAUDE_SKILL_DIR}/scripts/setup-wakatime.sh" apiurl wakapi

# Вариант 3 (custom):
bash "${CLAUDE_SKILL_DIR}/scripts/setup-wakatime.sh" apiurl "https://my-instance.example.com/api/compat/wakatime/v1"
```

**3.2 API ключ.** Спроси:
> «API ключ? Получи на:
> - WakaTime Cloud → https://wakatime.com/settings/api-key
> - wakapi.dev → залогинься на https://wakapi.dev → Profile → Settings → API Key
> - Self-hosted → admin вашего instance»

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/setup-wakatime.sh" apikey "<ключ>"
```

Принимаются оба формата: `waka_<uuid>` (WakaTime Cloud) и bare `<uuid>` (wakapi/self-hosted). Если скрипт ответил `API key не изменился` — отлично, шаг пропущен.

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

Скрипт делает две независимые проверки:

- **7.1 Валидация API ключа** — `GET /users/current` через HTTP Basic. Подтверждает что ключ принят сервером.
- **7.2 End-to-end доставка heartbeat** — фиксирует timestamp `t0`, отправляет тестовый heartbeat через хук, ждёт 3с, запрашивает `/heartbeats?date=today` и проверяет что есть запись с `time >= t0`. Это **настоящая проверка цели скилла**: не «bash отработал», а «heartbeat реально долетел до WakaTime».

Если тест провален — разбери причину и помоги пользователю:
- `API /users/current вернул HTTP 401` → ключ неверный, обнови (Шаг 3)
- `API ... вернул HTTP 5xx` → проблема на стороне WakaTime, попробуй позже
- `heartbeat отправлен, но не найден в API` → проверь системные часы, доступ wakatime-cli в интернет, права API ключа на запись
- `хук-скрипт упал` → проверь симлинку `~/.wakatime.cfg` (Шаг 5)

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
