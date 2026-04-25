---
name: day-close
description: "Протокол закрытия дня (Day Close). Симметрия с /day-open. Пошаговая фиксация итогов дня, обновление WeekPlan/MEMORY, backup."
argument-hint: ""
version: 2.0.0
---

# Day Close (протокол закрытия дня)

> **Роль:** R1 Стратег. **Один выход:** обновлённый DayPlan (секция «Итоги дня»), WeekPlan, MEMORY.md, exocortex backup.
> **Порядок:** строго пошагово. **Дата:** ПЕРВОЕ действие = `date`.
> **Симметрия:** `/day-open` открывает день, `/day-close` закрывает. Day Close ≠ Quick Close (Quick Close = сессия, Day Close = день).

## БЛОКИРУЮЩЕЕ: пошаговое исполнение

Day Close = протокол. Исполнять ТОЛЬКО пошагово через TodoWrite.
Каждый шаг алгоритма ниже → отдельная задача (pending → in_progress → completed).
Переход к следующему — ТОЛЬКО после отметки текущего. Шаг невозможен → blocked (не пропускать молча).

## Алгоритм

### 0. Extensions (before)

Проверить: `ls extensions/day-close.before.md`. Если существует → `Read extensions/day-close.before.md` → выполнить содержимое как первые шаги. Не существует → пропустить.

### 1. Сбор коммитов за сегодня

```bash
for repo in "$WORKSPACE_DIR"/*/; do
  [ -d "$repo/.git" ] || continue
  name=$(basename "$repo")
  commits=$(git -C "$repo" log --since="today 00:00" --oneline --no-merges 2>/dev/null)
  [ -n "$commits" ] && echo "=== $name ===" && echo "$commits"
done
```

- Сгруппировать по репозиториям
- Сопоставить с РП из WeekPlan
- Определить статус каждого затронутого РП: done / partial / not started

### 2. Обновить WeekPlan

Найти текущий `WeekPlan W*.md` в `DS-strategy/current/` и обновить:

- Пометь завершённые РП как **done** (зачёркнуть: `~~#~~ | ~~название~~`)
- Обнови статусы partial с описанием прогресса
- Добавь carry-over (что переносится) — в конец файла
- **НЕ удаляй** ничего — только помечать и дописывать

### 3. Обновить MEMORY.md

Синхронизировать статусы РП в MEMORY.md с обновлённым WeekPlan:

- done → done
- partial → in_progress (с пометкой прогресса)
- Удалить завершённые РП из pending, если они в done

### 4. Автоматические шаги (helper script)

Вызвать: `bash ./scripts/day-close.sh`

Это выполнит:
- Backup workspace memory/ (MEMORY.md, day-rhythm-config.yaml и др.) → exocortex/
- Knowledge-MCP reindex (изменённые за день источники)
- Linear sync (если настроен `linear_sync_path` в params.yaml)

Если скрипт не найден — выполнить backup вручную:
```bash
mkdir -p "$WORKSPACE_DIR/DS-strategy/exocortex"
cp ./workspaces/CURRENT_WORKSPACE/memory/*.md ./workspaces/CURRENT_WORKSPACE/memory/*.yaml "$WORKSPACE_DIR/DS-strategy/exocortex/" 2>/dev/null || true
cp ./workspaces/CURRENT_WORKSPACE/CLAUDE.md "$WORKSPACE_DIR/DS-strategy/exocortex/" 2>/dev/null || true
```

### 5. Мультипликатор IWE

Условие: `params.yaml → multiplier_enabled: true`.

1. Получить WakaTime за сегодня (API или CLI)
2. Бюджет закрыт = сумма бюджетов РП со статусом done/partial за сегодня
3. Мультипликатор = Бюджет закрыт / WakaTime
4. Записать в секцию «Мультипликатор IWE» (см. шаблон)

Если `multiplier_enabled: false` → пропустить.

### 6. Запись итогов дня в DayPlan

Найти текущий `DayPlan YYYY-MM-DD.md` в `DS-strategy/current/` (или `archive/day-plans/`).

Дописать секцию в конец (по шаблону из `persistent-memory/templates-dayplan.md § Шаблон итогов дня`):

- Таблица РП: что сделано / статус
- Коммиты за день
- Мультипликатор IWE (шаг 5)
- Что нового узнал
- Похвала
- **Завтра начать с:** ВСЕ pending РП — каждый с конкретным next action

Если DayPlan не найден — создать секцию «Итоги дня» как отдельный блок.

### 6b. Extensions (checks)

Проверить: `ls extensions/day-close.checks.md`. Если существует → `Read extensions/day-close.checks.md` → выполнить верификацию. БЛОКИРУЮЩЕЕ: commit запрещён до прохождения checks.

### 6c. Extensions (after)

Проверить: `ls extensions/day-close.after.md`. Если существует → `Read extensions/day-close.after.md` → выполнить содержимое (рефлексия, доп. проверки). Не существует → пропустить.

Условие: `params.yaml → reflection_enabled: false` → пропустить after-расширения.

### 7. Commit + Push

1. `git add` все изменения (WeekPlan, MEMORY.md, DayPlan, exocortex backup)
2. `git commit -m "day-close: YYYY-MM-DD"`
3. `git push`

**ЗАПРЕЩЕНО коммитить `inbox/fleeting-notes.md`!**

### 8. Compact dashboard (VS Code)

Вывести краткую сводку:

```
📋 Day Close: DD месяца YYYY

Коммиты: N в M репо
- repo-name: N коммитов (краткое описание)

РП обновлены в WeekPlan:
- #N: статус → новый статус

MEMORY.md: синхронизирован ✅
Exocortex backup: скопирован ✅
Git: закоммичен и запушен ✅

Завтра начать с:
1. #N — [next action]
```

### 9. Верификация (Haiku R23)

> Условный шаг: если `params.yaml → verify_quick_close: false` → пропустить.

Запустить sub-agent Haiku в роли R23 (context isolation). Передать:
- Чеклист Day Close
- DayPlan (секция «Итоги дня»)
- `git diff --name-only`

### Чеклист Day Close (для верификатора)

- [ ] Коммиты за день собраны и сопоставлены с РП
- [ ] WeekPlan обновлён (done помечены, carry-over записан)
- [ ] MEMORY.md синхронизирован с WeekPlan
- [ ] Backup выполнен (exocortex/)
- [ ] Мультипликатор IWE рассчитан (или отключён)
- [ ] DayPlan: секция «Итоги дня» записана
- [ ] «Завтра начать с» содержит ВСЕ pending РП с next actions
- [ ] Все изменения закоммичены и запушены
- [ ] extensions/checks пройдены (если есть)
