---
name: day-close
description: "Протокол закрытия дня (Day Close). Симметрия с /day-open. Пошаговая фиксация итогов дня, обновление WeekPlan/MEMORY, backup."
argument-hint: ""
version: 2.1.0
---

# Day Close (протокол закрытия дня)

> **Роль:** R1 Стратег. **Один выход:** обновлённый DayPlan (секция «Итоги дня»), WeekPlan, MEMORY.md.
> **Принцип:** SKILL.md = L1 платформенный файл. Пользователь не редактирует напрямую — только через `extensions/`.
> **Симметрия:** `/day-open` открывает день, `/day-close` закрывает. Day Close ≠ Quick Close (Quick Close = сессия, Day Close = день).

## БЛОКИРУЮЩЕЕ: пошаговое исполнение

Day Close = протокол. Исполнять ТОЛЬКО пошагово через TodoWrite.
**Шаг 0 — ПЕРВОЕ действие:** создать список задач прямо сейчас (до любых других действий).
Каждый шаг алгоритма → отдельная задача (pending → in_progress → completed).
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

Условие: `params.yaml → day_close_before_enabled: true`. Если `false` → пропустить.
Проверить: `ls $WORKSPACE_DIR/extensions/day-close.before.md`. Если существует → `Read` → выполнить как первые шаги.

### 2. Сбор данных

**2.1.** Прочитать сегодняшний DayPlan: `Read "$WORKSPACE_DIR/DS-strategy/current/DayPlan YYYY-MM-DD.md"`.
Если файла нет (ad-hoc день без Day Open) → пропустить сопоставление, работать из коммитов.

**2.2.** Запустить сбор коммитов:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/day-close.sh" --collect-data
```

**2.3.** Сопоставить коммиты с таблицей «На сегодня» из DayPlan → определить статусы:
- **done** — всё запланированное на день для РП закрыто коммитами
- **partial** — есть коммиты, но не все задачи закрыты
- **not started** — коммитов нет

### 3. Governance batch

**3a.** Обновить WeekPlan (`$WORKSPACE_DIR/DS-strategy/current/Plan W{N}...`): статусы РП. **Grep по номеру РП** — обновить ВСЕ упоминания.

**3b.** Обновить DayPlan `$WORKSPACE_DIR/DS-strategy/current/DayPlan YYYY-MM-DD.md`: статусы ВСЕХ строк (РП + ad-hoc). Done → зачеркнуть.

**3c.** Обновить `$WORKSPACE_DIR/DS-strategy/docs/WP-REGISTRY.md`: статусы + даты.

**3d.** Обновить `$WORKSPACE_DIR/DS-strategy/inbox/open-sessions.log`: удалить строки закрытых сессий.

**3e.** Governance-синхронизация: новые репо/сервисы за день?
  Проверить `$WORKSPACE_DIR/memory/persistent-memory/navigation.md`,
  обновить REPOSITORY-REGISTRY и MAP.002 при необходимости.

### 4. Архивация и синхронизация MEMORY.md

- Done WP context files → `mv "$WORKSPACE_DIR/DS-strategy/inbox/WP-{N}-*.md" "$WORKSPACE_DIR/DS-strategy/archive/wp-contexts/"`
- Done РП → удалить строку из `$WORKSPACE_DIR/memory/MEMORY.md` (они уже зафиксированы в WP-REGISTRY и WeekPlan)

> MEMORY.md хранит ТОЛЬКО активные РП (in_progress + pending). Done = удалить.

### 5. Memory Drift Scan

> Страховочная сетка — ловит то, что не обновили в Quick Close сессий за день.

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/day-close.sh" --drift-scan
```

Для каждого найденного паттерна:
1. Определить номер РП (WP-NNN) из контекста строки
2. Найти WP-context: `ls "$WORKSPACE_DIR/DS-strategy/inbox/WP-{N}-*.md"` (если заархивирован — `$WORKSPACE_DIR/DS-strategy/archive/wp-contexts/`)
3. Прочитать секцию «Что узнали» / «Осталось» / финальный статус
4. Если там есть признак закрытия (`DONE`, `РЕШЕНО`, `✅`, `починил`, `закрыт`, `снят`) → обновить $WORKSPACE_DIR/memory/MEMORY.md, анонс: *«Memory drift: [факт] устарел → обновлён»*
5. Если WP-context не найден → отметить в итогах: *«Memory drift: WP-N — context не найден, проверить вручную»*

Анонс при 0 изменениях: *«Drift-scan: проверено N паттернов, устаревших фактов не найдено»*

### 6. Index Health Check

> Ловит раздутие индекс-файлов (MEMORY.md, WP-REGISTRY.md, MAPSTRATEGIC.md, *-registry.md, *-index.md, *-catalog.md). Правило: hook-строки в индексах, не дамп контекста.
> **Условный шаг:** если скрипт отсутствует — пропустить.

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/day-close.sh" --index-health
```

Для каждого FAIL/WARN в отчёте:
1. Открыть файл, посмотреть конкретные строки из отчёта.
2. Диагностика: дамп контекста (болезнь) → перенести в source-of-truth; жанр-таблица → пометить `<!-- index-health: skip -->`.
3. Pack-файлы — не чистить автоматически, только пометить skip с обоснованием.

Анонс при 0 WARN/FAIL: *«Index-health: N файлов OK, M skip»*.

### 7. Lesson Hygiene

- Просмотреть секцию «Уроки» в $WORKSPACE_DIR/memory/MEMORY.md
- Урок применялся сегодня? → оставить
- Урок не применялся >1 нед и есть в тематическом файле (`lessons_*.md`)? → удалить из MEMORY.md
- Новый урок за день? → записать в MEMORY.md (краткая строка) + тематический файл (подробно)
- Цель: ≤8 уроков в MEMORY.md

### 8. Автоматические шаги (helper script)

Вызвать: `bash "${CLAUDE_SKILL_DIR}/scripts/day-close.sh" --backup-memory`

Это выполнит:
- Backup memory/ (commit + push MEMORY.md, day-rhythm-config.yaml и др. в workspace-репо, если `MEMORY_BACKUP=true` в .env)

> Knowledge-MCP reindex — пользовательское расширение, не платформенный шаг. Если нужен reindex: `$WORKSPACE_DIR/extensions/day-close.after.md`.

### 9. Мультипликатор IWE

> Условный шаг: вся логика — в расширении `$WORKSPACE_DIR/extensions/day-close.multiplier.md`.

Условие: `params.yaml → multiplier_enabled: true` (params.yaml в корне workspace).
Если `false` → пропустить.
Проверить: `ls "$WORKSPACE_DIR/extensions/day-close.multiplier.md"`. Если существует → `Read` → выполнить.

Исполнение расширения помещает в контекст значение мультипликатора, которое шаг 12 включит в DayPlan.

### 10. Черновик итогов (показать пользователю)

**а) Обзор:** таблица «что сделано» (РП × статус)

**б) Что нового узнал:** captures в Pack, различения, инсайты.

**в) Похвала:** что получилось, что было непросто но сделано.

**г) Не забыто?**
- Незакоммиченные изменения во всех репо. Если есть → закоммитить и запушить ДО продолжения.
- Незаписанные мысли? (спросить пользователя)
- Обещания кому-то? (спросить пользователя)

**д) Видео за день:** если `video.enabled: true` → проверить новые видео.

**е) Draft-list:** Pack обогащён → предложить черновик?

**ж) Задел на завтра:**
- С чего начать утром
- Незавершённые РП: что именно осталось (конкретный next action по каждому)

### 11. Согласование

Пользователь читает черновик → корректирует → одобряет.

### 12. Запись итогов

**12a.** Проверить `$WORKSPACE_DIR/memory/day-rhythm-config.yaml → day_open.strategy_day`:
- Если сегодня strategy_day → **НЕ создавать DayPlan** (Day Open не создаёт DayPlan в день стратегирования). Записать итоги только в WeekPlan (шаг 12b).
- Иначе: найти `DayPlan YYYY-MM-DD.md` в `$WORKSPACE_DIR/DS-strategy/current/`. Если не найден → создать файл `$WORKSPACE_DIR/DS-strategy/current/DayPlan YYYY-MM-DD.md`.

Дописать секцию «Итоги дня» в конец (по шаблону из `$FMT_DIR/persistent-memory/templates-dayplan.md § Шаблон итогов дня`):

- Таблица РП: что сделано / статус
- Коммиты за день
- Мультипликатор IWE (если рассчитан на шаге 9)
- Что нового узнал
- Похвала
- **Завтра начать с:** ВСЕ pending РП — каждый с конкретным next action

**Валидация «Завтра начать с» (ADR-207):** поле не пустое + каждый pending РП упомянут + каждый содержит конкретный next action (не «продолжить работу»).

**12b.** Дописать сводку итогов в WeekPlan:
- Формат: `<details><summary><b>Итоги {день} {дата}</b></summary>...</details>`
- Порядок: свежие итоги СВЕРХУ (обратная хронология)
- Содержание: таблица коммитов по репо, закрытые РП, продвинутые РП, мультипликатор

### 13. Extensions (checks)

Условие: `params.yaml → day_close_checks_enabled: true`. Если `false` → пропустить.
Проверить: `ls "$WORKSPACE_DIR/extensions/day-close.checks.md"`. Если существует → `Read` → выполнить верификацию. БЛОКИРУЮЩЕЕ: commit запрещён до прохождения checks.

### 14. Верификация (Haiku R23)

> Условный шаг: если `params.yaml → verify_quick_close: false` → пропустить.

Запустить sub-agent Haiku в роли R23 (context isolation). Передать:
- Чеклист Day Close (ниже)
- DayPlan (секция «Итоги дня»)
- Список изменённых файлов: `git diff --cached --name-only`

По ❌ — исправить до завершения. **Commit запрещён до прохождения.**

### 15. Commit + Push

> MEMORY.md уже закоммичен шагом 8 (`day-close.sh --backup-memory`). Здесь — только governance-файлы.

```bash
DS="$WORKSPACE_DIR/DS-strategy"
TODAY=$(date +%Y-%m-%d)

if git -C "$DS" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$DS" add \
    "current/DayPlan $TODAY.md" \
    current/Plan\ W*.md \
    docs/WP-REGISTRY.md \
    inbox/open-sessions.log
  git -C "$DS" commit -m "day-close: $TODAY" 2>&1 || echo "(нет изменений для коммита)"
  git -C "$DS" push 2>&1 || echo "(push не удался, коммит сохранён локально)"
else
  echo "DS-strategy не git-репозиторий — governance commit пропущен"
fi
```

**ЗАПРЕЩЕНО коммитить `$WORKSPACE_DIR/DS-strategy/inbox/fleeting-notes.md`!**

### 16. Compact dashboard

Вывести краткую сводку:

```
Day Close: DD месяца YYYY

Коммиты: N в M репо
- repo-name: N коммитов (краткое описание)

РП обновлены в WeekPlan:
- #N: статус → новый статус

MEMORY.md: синхронизирован ✅
Backup memory: выполнен ✅
Git: закоммичен и запушен ✅

Завтра начать с:
1. #N — [next action]
```

### 17. Extensions (after)

Условие: `params.yaml → day_close_after_enabled: true`. Если `false` → пропустить.
Проверить: `ls "$WORKSPACE_DIR/extensions/day-close.after.md"`. Если существует → `Read` → выполнить содержимое (рефлексия, доп. проверки).

---

## Чеклист Day Close (для верификатора)

- [ ] Коммиты за день собраны, сопоставлены с DayPlan «На сегодня», статусы определены
- [ ] WeekPlan обновлён (grep по номерам РП — ВСЕ упоминания)
- [ ] DayPlan обновлён (статусы ВСЕХ строк: РП + ad-hoc)
- [ ] WP-REGISTRY.md обновлён (статусы + даты)
- [ ] DS-strategy/inbox/open-sessions.log: строки закрытых сессий удалены
- [ ] memory/MEMORY.md: done-РП удалены, активные актуальны
- [ ] Drift-scan выполнен (шаг 5)
- [ ] Index Health Check выполнен или пропущен (шаг 6)
- [ ] Lesson Hygiene: уроки MEMORY.md ≤8
- [ ] WP context: done → перемещены в DS-strategy/archive/wp-contexts/
- [ ] Backup выполнен (day-close.sh, шаг 8)
- [ ] Мультипликатор IWE рассчитан (если extensions/day-close.multiplier.md существует) или пропущен
- [ ] Черновик итогов показан и согласован с пользователем
- [ ] DayPlan: секция «Итоги дня» записана
- [ ] «Завтра начать с» содержит ВСЕ pending РП с конкретным next action
- [ ] WeekPlan: сводка итогов дописана (details, обратная хронология)
- [ ] Extensions checks пройдены (если есть)
- [ ] Все изменения закоммичены и запушены
- [ ] Governance: REPOSITORY-REGISTRY, navigation.md, MAP.002 (если новые репо/сервисы)

Все ✅ → «День закрыт.» Иначе — указать что осталось.
