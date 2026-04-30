---
name: wp-new
description: Создание нового рабочего продукта (РП) с записью в 5 мест атомарно. Используй когда появляется новая задача, которой нет в плане недели.
argument-hint: "[название РП]"
---

# Создание нового РП

Новый рабочий продукт: $ARGUMENTS

## Шаг 0. Разрешить WORKSPACE_DIR

Выполнить блок ниже, запомнить `WORKSPACE_DIR` из вывода. Использовать во всех последующих шагах.

```bash
source "${CLAUDE_SKILL_DIR}/../../scripts/resolve-workspace.sh"
resolve_fmt_dir && resolve_workspace
echo "WORKSPACE_DIR=$WORKSPACE_DIR"
```

## Шаг 1. Сбор информации

Запроси или определи:
- **Название:** формулировка артефакта (не задачи)
- **Репо:** целевой репозиторий
- **Бюджет:** оценка в часах
- **Приоритет:** критический / высокий / средний / низкий
- **Результат месяца:** (только для РП ≥3h) к какому результату месяца (R1, R2, …) привязан? Допустимые ответы: R{N}, поддержка, off-plan. Source-of-truth маппинга: `$WORKSPACE_DIR/DS-strategy/docs/Strategy.md` → «РП → Результаты»
- **Критерий готовности:** что должно получиться

## Шаг 2. Нумерация

Найди последний номер РП в `$WORKSPACE_DIR/memory/MEMORY.md` → следующий порядковый номер. Только целые числа (74, 75…). Буквенные суффиксы (73a, 73b) запрещены.

## Шаг 3. Проверка бюджета

Прочитай текущий бюджет недели из `$WORKSPACE_DIR/DS-strategy/current/Plan\ W*.md`. Предупреди если превышение.

## Шаг 4. Атомарная запись в 5 мест

1. **MEMORY.md** → таблица «РП текущей недели» в `$WORKSPACE_DIR/memory/MEMORY.md` (новая строка)
2. **DS-strategy/docs/WP-REGISTRY.md** → новая строка в `$WORKSPACE_DIR/DS-strategy/docs/WP-REGISTRY.md` (сортировка: от последнего к первому)
3. **DS-strategy/current/WeekPlan W{N}...** → таблица РП в `$WORKSPACE_DIR/DS-strategy/current/Plan\ W*.md` (новая строка)
4. **DS-strategy/docs/Strategy.md** → таблица «РП → Результаты» в `$WORKSPACE_DIR/DS-strategy/docs/Strategy.md` (только для РП ≥3h, добавить строку с маппингом)
5. **DS-strategy/inbox/WP-{N}-{slug}.md** → context file в `$WORKSPACE_DIR/DS-strategy/inbox/WP-{N}-{slug}.md`:

```markdown
---
wp: {N}
title: {название}
status: pending
created: {YYYY-MM-DD}
source: {откуда пришла задача}
verification_class: {closed-loop | open-loop | problem-framing}
---

# WP-{N}: {название}

## Описание
{что и зачем}

## Артефакт
{конкретный результат}

## Контекст
{связи, зависимости}

## Критерий готовности
{чеклист}

## Бюджет
~{N}h

## Осталось
Всё — не начато.
```

## Шаг 5. Подтверждение

Выведи: *«РП #{N} создан. Записан в MEMORY, Registry, WeekPlan, Strategy (маппинг), context file.»*
Если РП <3h: *«РП #{N} создан. Записан в MEMORY, Registry, WeekPlan, context file. (маппинг к результату не требуется, бюджет <3h)»*
