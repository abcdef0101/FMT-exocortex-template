---
name: week-close
description: "Протокол закрытия недели (Week Close). Симметрия с /day-open. Сбор итогов недели, ротация уроков, аудит memory, создание поста для клуба."
argument-hint: ""
version: 2.0.0
---

# Week Close (протокол закрытия недели)

> **Роль:** R1 Стратег. **Выходы:** секция «Итоги W{N}» в WeekPlan, пост для клуба, обновлённый MEMORY.md, memory audit report.
> **Порядок:** строго пошагово. **Дата:** ПЕРВОЕ действие = `date`.
> **Триггер:** «закрываю неделю» / «итоги недели». Запускается в конце недели (обычно воскресенье).

## БЛОКИРУЮЩЕЕ: пошаговое исполнение

Week Close = протокол. Исполнять ТОЛЬКО пошагово через TodoWrite.
Каждый шаг алгоритма ниже → отдельная задача (pending → in_progress → completed).
Переход к следующему — ТОЛЬКО после отметки текущего. Шаг невозможен → blocked (не пропускать молча).

## Алгоритм

### 0. Разрешить WORKSPACE_DIR и FMT_DIR

Выполнить блок ниже, запомнить `FMT_DIR` и `WORKSPACE_DIR` из вывода. Использовать во всех последующих шагах.

```bash
source "${CLAUDE_SKILL_DIR}/../../scripts/resolve-workspace.sh"
resolve_fmt_dir && resolve_workspace
echo "FMT_DIR=$FMT_DIR"
echo "WORKSPACE_DIR=$WORKSPACE_DIR"
```

### 1. Extensions (before)

Условие: `$WORKSPACE_DIR/params.yaml → week_close_before_enabled: true`. Если `false` → пропустить.
Проверить: `ls "$WORKSPACE_DIR/extensions/week-close.before.md"`. Если существует → `Read` → выполнить содержимое как первые шаги. Не существует → пропустить.

### 2. Ротация уроков

Условие: `$WORKSPACE_DIR/params.yaml → lesson_rotation: true`. Если `false` → пропустить.

Для каждого урока в `$WORKSPACE_DIR/memory/MEMORY.md` → секция «Уроки»:
1. Применялся за последние 2 недели? (инцидент, упоминание в Close-отчётах, или урок < 2 недель)
2. **Да** → оставить
3. **Нет** → вынести в `$WORKSPACE_DIR/memory/lessons-archive.md` (не загружается автоматически)
4. Цель: ≤15 актуальных уроков в MEMORY.md

### 3. Сбор данных недели

```bash
MONDAY=$(date -d "last monday" +%Y-%m-%d)
SUNDAY=$(date +%Y-%m-%d)
for repo in "$WORKSPACE_DIR"/*/; do
  [ -d "$repo/.git" ] || continue
  name=$(basename "$repo")
  commits=$(git -C "$repo" log --since="$MONDAY 00:00" --until="$SUNDAY 23:59:59" --oneline --no-merges 2>/dev/null)
  [ -n "$commits" ] && echo "=== $name ===" && echo "$commits"
done
```

- Пройти по ВСЕМ репозиториям
- Загрузить текущий WeekPlan из `$WORKSPACE_DIR/DS-strategy/current/`
- Сопоставить коммиты с РП из WeekPlan
- Определить статус каждого РП: done / partial / not started

### 4. Статистика

- Completion rate: X/Y РП (N%)
- Коммитов всего
- Активных дней (дни с коммитами)
- По репозиториям (таблица)
- По системам (если применимо)

### 5. Инсайты

- Что получилось хорошо
- Что можно улучшить
- Блокеры (если были)
- Carry-over на следующую неделю

### 6. Контент-план на следующую неделю

1. Собрать Content ideas за неделю (из `$WORKSPACE_DIR/DS-strategy/drafts/draft-list.md`, captures, Close-отчётов)
2. Сопоставить с backlog публикаций из Стратегии маркетинга
3. Предложить 2-3 публикации:
   - Что адаптировать (источник)
   - Для кого (сегмент)
   - Куда (канал)
4. Записать контент-план в секцию «Итоги W{N}»

### 7. Свежая таблица РП в MEMORY.md

1. Удалить ВСЕ РП прошлой недели из `$WORKSPACE_DIR/memory/MEMORY.md`
2. Проверить `$WORKSPACE_DIR/DS-strategy/current/Plan\ W{N+1}*.md`:
   - Если WeekPlan на новую неделю создан (strategy session) → заполнить таблицу из него
   - Если WeekPlan отсутствует → оставить таблицу пустой с пометкой «ожидает strategy session»
3. Перенести из старого WeekPlan:
   - in_progress и pending → в новую таблицу
   - done → НЕ переносить (уже в WP-REGISTRY)
4. Обновить заголовок: `W{N+1}: DD мес – DD мес`

### 8. Запись итогов в WeekPlan

1. Открыть текущий `$WORKSPACE_DIR/DS-strategy/current/Plan\ W{N}*.md`
2. Найти или создать секцию `## Итоги W{N}`
3. Записать: метрики, таблицу по репо, статусы РП, инсайты, carry-over, контент-план
4. Использовать шаблон из `$FMT_DIR/roles/strategist/prompts/week-review.md § Шаблон секции`

### 9. Создать пост для клуба

1. На основе секции «Итоги W{N}» сформировать пост
2. Frontmatter:
```yaml
---
type: post
title: "..."
audience: community
status: ready
created: YYYY-MM-DD
target: club
source_knowledge: null
tags: [итоги-недели, W{N}]
content_plan: null
---
```

3. Записать ссылку на пост в WeekPlan

### 10. Аудит memory-файлов

1. Количество файлов в `$WORKSPACE_DIR/memory/`: ≤11 файлов? Лишние → объединить или удалить
2. Лимиты строк:
   - Справочники (hard-distinctions, navigation, roles, sota) ≤ 100
   - Протоколы (protocol-*) ≤ 150
   - MEMORY.md ≤ 100
3. Устаревшие записи → обновить или удалить
4. Результат: отчёт «Memory audit: N файлов, M строк суммарно, K обновлено»

### 11. Ревью культуры работы IWE (DP.M.008 #14)

Запустить `/iwe-rules-review` → отчёт → согласование → обновление DP.M.008 + реализаций.

### 12. Extensions (after)

Условие: `$WORKSPACE_DIR/params.yaml → week_close_after_enabled: true`. Если `false` → пропустить.
Проверить: `ls "$WORKSPACE_DIR/extensions/week-close.after.md"`. Если существует → `Read` → выполнить содержимое. Не существует → пропустить.

### 13. Верификация (Haiku R23)

> Условный шаг: если `$WORKSPACE_DIR/params.yaml → verify_quick_close: false` → пропустить.

Запустить sub-agent Haiku в роли R23 (context isolation). Передать:
- Чеклист Week Close (ниже)
- WeekPlan (секция «Итоги W{N}»)
- Список изменённых файлов: `git -C "$WORKSPACE_DIR/DS-strategy" diff --cached --name-only`

По ❌ — исправить до завершения. **Commit запрещён до прохождения.**

### 14. Commit + Push

```bash
DS="$WORKSPACE_DIR/DS-strategy"
TODAY=$(date +%Y-%m-%d)

if git -C "$DS" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$DS" add current/Plan\ W*.md docs/WP-REGISTRY.md
  git -C "$DS" commit -m "week-close: W{N} $TODAY" 2>&1 || echo "(нет изменений)"
  git -C "$DS" push 2>&1 || echo "(push не удался, коммит сохранён локально)"
else
  echo "DS-strategy не git-репозиторий — governance commit пропущен"
fi
```

### 15. Compact dashboard (VS Code)

Вывести краткую сводку:

```
📋 Week Close: W{N} (DD мес — DD мес YYYY)

РП: X/Y завершено (N%)
Коммитов: N в M репо
Активных дней: N/7

Carry-forward на W{N+1}:
- #N — [описание]

MEMORY.md: обновлён ✅
Уроки: ротация выполнена / отключена
Ревью культуры: выполнено / пропущено
Memory audit: N файлов, M строк, K обновлено
Пост для клуба: создан ✅
Git: закоммичено и запушено ✅
```

### Чеклист Week Close (для верификатора)

- [ ] Уроки: ротация выполнена (или отключена)
- [ ] Коммиты недели собраны и сопоставлены с РП
- [ ] Статистика и инсайты записаны
- [ ] Контент-план на следующую неделю предложен
- [ ] MEMORY.md: таблица РП обновлена на новую неделю
- [ ] WeekPlan: секция «Итоги W{N}» записана
- [ ] Пост для клуба создан
- [ ] Ссылка на пост в WeekPlan
- [ ] Memory audit выполнен (≤11 файлов, лимиты соблюдены)
- [ ] Ревью культуры работы: `/iwe-rules-review` выполнен, изменения применены
- [ ] Extensions пройдены (если есть)
- [ ] Все изменения закоммичены и запушены
