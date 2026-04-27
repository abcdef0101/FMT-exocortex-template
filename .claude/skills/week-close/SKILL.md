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

### 0. Extensions (before)

Условие: `params.yaml → week_close_before_enabled: true`. Если `false` → пропустить.
Проверить: `ls extensions/week-close.before.md`. Если существует → `Read extensions/week-close.before.md` → выполнить содержимое как первые шаги. Не существует → пропустить.

### 1. Ротация уроков

Условие: `params.yaml → lesson_rotation: true`. Если `false` → пропустить.

Для каждого урока в MEMORY.md → секция «Уроки»:
1. Применялся за последние 2 недели? (инцидент, упоминание в Close-отчётах, или урок < 2 недель)
2. **Да** → оставить
3. **Нет** → вынести в `memory/lessons-archive.md` (не загружается автоматически)
4. Цель: ≤15 актуальных уроков в MEMORY.md

### 2. Сбор данных недели

```bash
WORKSPACE_DIR="$(cd "workspaces/CURRENT_WORKSPACE" && pwd)"
for repo in "$WORKSPACE_DIR"/*/; do
  [ -d "$repo/.git" ] || continue
  name=$(basename "$repo")
  commits=$(git -C "$repo" log --since="last monday 00:00" --until="today 00:00" --oneline --no-merges 2>/dev/null)
  [ -n "$commits" ] && echo "=== $name ===" && echo "$commits"
done
```

- Пройти по ВСЕМ репозиториям
- Загрузить текущий WeekPlan из `DS-strategy/current/`
- Сопоставить коммиты с РП из WeekPlan
- Определить статус каждого РП: done / partial / not started

### 3. Статистика

- Completion rate: X/Y РП (N%)
- Коммитов всего
- Активных дней (дни с коммитами)
- По репозиториям (таблица)
- По системам (если применимо)

### 4. Инсайты

- Что получилось хорошо
- Что можно улучшить
- Блокеры (если были)
- Carry-over на следующую неделю

### 4b. Контент-план на следующую неделю

1. Собрать Content ideas за неделю (из draft-list.md, captures, Close-отчётов)
2. Сопоставить с backlog публикаций из Стратегии маркетинга
3. Предложить 2-3 публикации:
   - Что адаптировать (источник)
   - Для кого (сегмент)
   - Куда (канал)
4. Записать контент-план в секцию «Итоги W{N}»

### 5. Свежая таблица РП в MEMORY.md

1. Удалить ВСЕ РП прошлой недели из MEMORY.md
2. Заполнить таблицу из нового WeekPlan:
   - in_progress и pending → перенести
   - done → НЕ переносить (уже в WP-REGISTRY)
3. Обновить заголовок: `W{N+1}: DD мес – DD мес`

### 6. Запись итогов в WeekPlan

1. Открыть текущий `WeekPlan W{N}*.md`
2. Найти или создать секцию `## Итоги W{N}`
3. Записать: метрики, таблицу по репо, статусы РП, инсайты, carry-over, контент-план
4. Использовать шаблон из `roles/strategist/prompts/week-review.md § Шаблон секции`

### 7. Создать пост для клуба

1. Переключиться на роль Автора (R4)
2. На основе секции «Итоги W{N}» сформировать пост
3. Frontmatter:
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

4. Записать ссылку на пост в WeekPlan

### 8. Аудит memory-файлов

1. Количество: ≤11 файлов? Лишние → объединить или удалить
2. Лимиты строк:
   - Справочники (hard-distinctions, navigation, roles, sota) ≤ 100
   - Протоколы (protocol-*) ≤ 150
   - MEMORY.md ≤ 100
3. Устаревшие записи → обновить или удалить
4. Результат: отчёт «Memory audit: N файлов, M строк суммарно, K обновлено»

### 8b. Extensions (after)

Условие: `params.yaml → week_close_after_enabled: true`. Если `false` → пропустить.
Проверить: `ls extensions/week-close.after.md`. Если существует → `Read extensions/week-close.after.md` → выполнить содержимое. Не существует → пропустить.

### 9. Commit + Push

1. `git add` все изменения
2. `git commit -m "week-close: W{N} YYYY-MM-DD"`
3. `git push`

### 10. Compact dashboard (VS Code)

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
Memory audit: N файлов, M строк, K обновлено
Пост для клуба: создан ✅
Git: закоммичено и запушено ✅
```

### 11. Верификация (Haiku R23)

Запустить sub-agent Haiku в роли R23 (context isolation). Передать:
- Чеклист Week Close
- WeekPlan (секция «Итоги W{N}»)
- `git diff --name-only`

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
- [ ] Все изменения закоммичены и запушены
- [ ] extensions пройдены (если есть)
