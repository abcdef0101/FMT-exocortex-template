---
name: role-create
description: "Создание новой роли. Интерактивный диалог: определяет L1 (обязанности) → L2 (SOP) → L3 (реализация) → генерирует agent definition + prompts. Используй когда нужно создать новую роль или агента."
argument-hint: "[имя роли или описание]"
user_invocable: true
version: 2.0.0
---

# Создание роли (Role Creator)

> **Роль:** R5 Архитектор (проектирование) → R6 Кодировщик (генерация)
> **Формат:** Agent definition (.opencode/agents/*.md) + prompts/ + scripts/

Создание роли: $ARGUMENTS

## Шаг 0. Загрузка контекста

Определить ROOT_DIR (корень репо — где находится CLAUDE.md).
Создать выходную директорию: `/tmp/role-{name}/`

Если аргумент содержит имя — использовать как `{name}` (lowercase, без пробелов).
Если аргумент — описание — предложить имя на основе описания.

## Шаг 1. Определение роли (L1) — ИНТЕРАКТИВ

> **БЛОКИРУЮЩЕЕ.** Не переходить к Шагу 2 без ответов на ВСЕ блокирующие вопросы.

### Блокирующие вопросы (задать ВСЕ одним сообщением)

**Б1.** «Название роли?» → `display_name`, `name` (auto-slug)

**Б2.** «ID роли?» → `id` (R{N} для платформенных, U.R{N} для пользовательских)

**Б3.** «Тип роли?» → `type`
  - `agential` — ИИ-агент (Grade 2+), действует автономно
  - `functional` — скрипт/автоматизация (Grade 0+)

**Б4.** «Надсистема?» → `suprasystem`

**Б5.** «Bounded Context?» → `context`

**Б6.** «Обязанности роли? (2-5 пунктов)» → `obligations`

### Уточняющие вопросы

**У1.** «Различение?» → `distinction`
**У2.** «Исполнители?» → `potential_holders`
**У3.** «Ожидания от роли?» → `expectations`
**У4.** «Failure modes?» → `failure_modes`
**У5.** «Связанные роли?» → `related_roles`
**У6.** «Рабочие продукты?» → `work_products`

### Показать черновик L1 → подтвердить

## Шаг 2. SOP роли (L2) — ИНТЕРАКТИВ

**В2.1.** «Методы? (2-5)» → `methods`
**В2.2.** «Сценарии запуска?» → `scenarios`
**В2.3.** «Минимальный Grade?» → `grade`
**В2.4.** «Стилистические ограничения?» → `behavioral_constraints`

Показать черновик L2 → подтвердить

## Шаг 3. Реализация (L3) — ИНТЕРАКТИВ

### Обязательные

**Л3.1.** «Режим агента?» → `mode`
  - `primary` — пользователь общается напрямую, полный контекст
  - `subagent` — вызывается через Task tool, context isolation
  - `all` — оба режима

**Л3.2.** «Модель?» → `model`
  - `sonnet` — стандартный (большинство ролей)
  - `opus` — для сложных задач (archgate, глубокий аудит)
  - `haiku` — для быстрых задач

**Л3.3.** «Permissions?» → `permission`
  - `edit: allow/deny` — запись файлов
  - `bash: allow/deny` — выполнение команд
  - `skill: "skill-*": allow` — какие skills доступны

**Л3.4.** «Hidden?» → `hidden` (только для subagent)

**Л3.5.** «Нужен runner-скрипт?» → `runner`

**Л3.6.** «Нужны timed-триггеры (launchd/systemd)?» → `install`

### Показать черновик L3 → подтвердить

## Шаг 4. Генерация артефактов

> Все файлы создаются в `/tmp/role-{name}/`.

### 4.1. Agent definition: `{name}.md`

Основной артефакт. Создаётся в `.opencode/agents/`.

```markdown
---
description: "{id} {display_name} — {context}. Загружает skill: {список skills}."
mode: {mode}
hidden: {true/false, только subagent}
model: {provider/model-id}
permission:
  edit: {allow/deny}
  bash: {allow/deny}
  read: allow
  glob: allow
  grep: allow
  skill:
    "{skill-pattern}": "allow"
---

Ты {id} {display_name}. {context}.

## Когда активен
{scenarios — таблица trigger → что делает}

## Алгоритм
1. {шаги из L2 methods}
2. Загрузи нужный skill через skill tool
3. {выполнение}

## Ограничения
{failure_modes как guardrails}
{behavioral_constraints}
```

### 4.2. Prompts: `prompts/{scenario}.md`

Один файл на каждый scenario из L2:

```markdown
# {scenario_name}

> Роль: {id} {display_name}
> Сценарий: {scenario_name}

## Контекст
{scenario description}

## Вход
{inputs}

## Алгоритм
{method description}

## Выход
{work_product}

## Ограничения
{behavioral_constraints guardrails}
```

### 4.3. Scripts (если нужен runner)

**С bash-раннером:**
```bash
#!/usr/bin/env bash
# {name}.sh — runner для {display_name}
set -euo pipefail
# Запускает AI-агента с нужным промптом
```

**С timed-триггерами:**
- `scripts/{name}.sh` — runner
- `scripts/launchd/com.{name}.{trigger}.plist` — macOS
- `scripts/systemd/exocortex-{name}-{trigger}.{service,timer}` — Linux

## Шаг 5. Верификация

| Проверка | Что |
|----------|-----|
| Agent definition полнота | description, mode, model, permission заполнены |
| Agent definition формат | Valid YAML frontmatter |
| Prompts полнота | Один файл на каждый scenario |
| Scripts существуют | Если указан runner — файл создан |
| mode консистентность | subagent + hidden = ok; primary + hidden = error |
| permission консистентность | edit: deny для read-only ролей; edit: allow для write-ролей |

## Шаг 6. Результат

Вывести:

**Дерево файлов:**
```
/tmp/role-{name}/
├── {name}.md           → .opencode/agents/
├── prompts/
│   └── {scenario}.md   → roles/{name}/prompts/
└── scripts/            → roles/{name}/scripts/ (если есть)
    ├── {name}.sh
    └── launchd/ | systemd/
```

**Инструкция по установке:**
1. Скопировать `{name}.md` → `.opencode/agents/{name}.md`
2. Создать `roles/{name}/prompts/` и перенести промпты
3. Если есть scripts — перенести в `roles/{name}/scripts/`
4. Если есть timed-триггеры — добавить в setup.sh autodiscovery
5. Добавить описание роли в DP.ROLE.001 §3.2 (если платформенная)
6. Описание роли в `persistent-memory/roles.md`
