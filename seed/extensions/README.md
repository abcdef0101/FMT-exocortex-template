# Extensions (пользовательские расширения)

> Эта директория — ваше пространство. `update.sh` **никогда** не трогает файлы здесь.

## Как расширить протокол

Создайте файл с именем `<protocol>.<hook>.md`, где:
- `<protocol>` — имя протокола (`protocol-close`, `protocol-open`, `day-open`)
- `<hook>` — точка вставки (`before`, `after`, `checks`)

### Поддерживаемые extension points

| Протокол | Hook | Когда выполняется |
|----------|------|-------------------|
| `protocol-close` | `checks` | После Step 1 (commit+push), перед Step 2 (статусы) |
| `protocol-close` | `after` | После основного чеклиста, перед верификацией |
| `day-open` | `before` | Перед шагом 1 (Вчера) — утренние ритуалы, подготовка |
| `day-open` | `after` | После шага 6b (Требует внимания), перед записью DayPlan |
| `day-open` | `checks` | Перед commit DayPlan (БЛОКИРУЮЩЕЕ) |
| `day-close` | `before` | Перед шагом 1 |
| `day-close` | `checks` | После governance batch, перед архивацией |
| `day-close` | `multiplier` | После механических шагов (шаг 4), перед записью итогов (шаг 6) |
| `day-close` | `after` | После итогов дня, перед верификацией |
| `week-close` | `before` | Перед ротацией уроков (шаг 1) |
| `week-close` | `after` | После аудита memory (шаг 4), перед финализацией |
| `protocol-open` | `after` | После ритуала согласования |

### Пример: рефлексия дня

Файл `extensions/day-close.after.md`:

```markdown
## Рефлексия дня

- Что сегодня было самым сложным?
- Что бы я сделал иначе?
- За что себя похвалить?
```

При Day Close агент автоматически подгрузит этот блок в соответствующую точку протокола.

### Временное отключение

Каждый extension point имеет toggle в `params.yaml` (формат: `{protocol}_{hook}_enabled`). Установите `false`, чтобы пропустить шаг без удаления файла:

```yaml
# Отключить мультипликатор без удаления файла
multiplier_enabled: false

# Отключить утренние ритуалы
day_open_before_enabled: false
```

### Пример: дополнительные проверки при закрытии сессии

Файл `extensions/protocol-close.checks.md`:

```markdown
- [ ] Проверить что тесты проходят (pytest / npm test)
- [ ] Обновить CHANGELOG.md если были feat-коммиты
```

## Параметры (params.yaml)

Файл `params.yaml` содержит персистентные параметры, влияющие на поведение протоколов.
`update.sh` **не перезаписывает** params.yaml — ваши настройки в безопасности.

| Параметр | Протокол | Что управляет |
|----------|----------|---------------|
| `day_open_before_enabled` | Day Open | Before-extension (утренние ритуалы) |
| `video_check` | Day Open | Проверка видео за прошлый день |
| `day_open_after_enabled` | Day Open | After-extension |
| `day_open_checks_enabled` | Day Open | Checks-extension |
| `day_close_before_enabled` | Day Close | Before-extension |
| `multiplier_enabled` | Day Close | Расчёт мультипликатора IWE |
| `day_close_checks_enabled` | Day Close | Checks-extension |
| `day_close_after_enabled` | Day Close | After-extension (рефлексия, доп. проверки) |
| `week_close_before_enabled` | Week Close | Before-extension |
| `week_close_after_enabled` | Week Close | After-extension |
| `lesson_rotation` | Week Close | Ротация уроков в MEMORY.md |
| `protocol_open_after_enabled` | Protocol Open | After-extension |
| `protocol_close_checks_enabled` | Protocol Close | Checks-extension |
| `protocol_close_after_enabled` | Protocol Close | After-extension |
| `auto_verify_code` | Quick Close | Автоверификация кода Haiku |
| `verify_quick_close` | Quick Close | Верификация чеклиста Haiku |
| `telegram_notifications` | Все роли | Telegram уведомления от ролей |
| `extensions_dir` | Все протоколы | Директория расширений (default: `extensions`) |

Подробности: [params.yaml](../params.yaml).

## Конфиг Day Open (day-rhythm-config.yaml)

Поведение Day Open управляется через `workspaces/<ws>/memory/day-rhythm-config.yaml` (не params.yaml).

| Параметр | Что управляет |
|----------|---------------|
| `budget_spread.enabled` | Распределять недельный бюджет РП по дням (true/false) |
| `budget_spread.threshold_h` | Минимальный недельный бюджет для участия в расчёте (по умолчанию: 4h) |
| `budget_spread.rounding` | Шаг округления daily_slot (по умолчанию: 0.5h) |

**Пример:** РП с бюджетом 6h/нед, среда (days_left=3) → daily_slot = round(6/3, 0.5) = 2h.

## Несколько расширений одного hook (конфликты имён)

Если нужно два расширения в одной точке — добавьте суффикс через точку:

```
extensions/day-close.after.md          # основное
extensions/day-close.after.health.md   # дополнительное (например, от другого пакета)
```

Загружаются в **алфавитном порядке** — конфликта нет, оба выполнятся.

## Установка чужого расширения (sharing)

Расширения IWE — обычные Markdown-файлы. Установка:

```bash
cp ~/Downloads/day-close.after.health.md ~/IWE/extensions/
```

### Формат пакета расширений (bundle)

```
my-extension-pack/
  README.md                    # описание, автор, версия
  extensions/
    day-close.after.md          # файлы расширений
  params-defaults.yaml          # рекомендуемые параметры (не применяются автоматически)
```

Установка bundle:

```bash
cp my-extension-pack/extensions/* ~/IWE/extensions/
# Просмотреть params-defaults.yaml и добавить нужные параметры в ~/IWE/params.yaml вручную
```

Посмотреть все доступные extension points: `/extend`

## Подключение своего MCP (mcp-user.json)

Добавьте свои MCP-серверы в `extensions/mcp-user.json`. При каждом `update.sh` они автоматически мёржатся в `.mcp.json`.

### Namespace соглашение

| Префикс | Кто | Примеры |
|---------|-----|---------|
| без префикса | Платформенные (зарезервированы) | `iwe-knowledge` (Gateway, агрегирует knowledge + digital-twin) |
| `ext-*` | Вендорские | `ext-google-calendar`, `ext-linear`, `ext-slack` |
| `<ваш префикс>-*` | Ваши MCP | `tseren-notes`, `tseren-obsidian` |

Используйте свой уникальный префикс (например username) — это предотвращает конфликты при обновлениях.

### Пример: добавить свой MCP

Файл `extensions/mcp-user.json`:

```json
{
  "mcpServers": {
    "user-my-notes": {
      "command": "npx",
      "args": ["-y", "my-notes-mcp"],
      "env": {
        "NOTES_DIR": "/path/to/my/notes"
      }
    },
    "ext-linear": {
      "command": "npx",
      "args": ["-y", "@mseep/linear-mcp"],
      "env": {
        "LINEAR_API_KEY": "lin_api_..."
      }
    }
  }
}
```

После `update.sh` эти серверы появятся в `.mcp.json`. Требуется `jq` (`brew install jq`).

**Важно:** `update.sh` не трогает `extensions/mcp-user.json` — ваши MCP в безопасности при обновлениях.

## Правила

1. Имена файлов: `<protocol>.<hook>.md` или `<protocol>.<hook>.<suffix>.md`
2. Содержимое: markdown, будет вставлен как блок в протокол
3. `update.sh` не трогает `extensions/` — ваши файлы в безопасности
4. Несколько расширений одного hook: загружаются в алфавитном порядке

## Script Extensions

Помимо markdown-расширений, `extensions/` может содержать исполняемые скрипты-обёртки для интеграций:

| Скрипт | Протокол | Описание |
|--------|----------|----------|
| `linear-sync.sh` | day-close (шаг 4b) | Синхронизация с Linear. Читает `params.yaml → linear_sync_path` и вызывает внешний скрипт с `--workspace-dir`. Если путь не указан — тихо пропускается |
