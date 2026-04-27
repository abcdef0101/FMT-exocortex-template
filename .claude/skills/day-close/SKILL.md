---
name: day-close
description: "Протокол закрытия дня (Day Close). Симметрия с /day-open. Пошаговая фиксация итогов дня, обновление WeekPlan/MEMORY, backup."
argument-hint: ""
allowed-tools: Bash(bash "${CLAUDE_SKILL_DIR}/scripts/day-close.sh" *)
version: 2.1.0
---

# Day Close (протокол закрытия дня)

> **Роль:** R1 Стратег. **Один выход:** обновлённый DayPlan (секция «Итоги дня»), WeekPlan, MEMORY.md, exocortex backup.
> **Принцип:** SKILL.md = L1 платформенный файл. Пользователь не редактирует напрямую — только через `extensions/`.
> **Симметрия:** `/day-open` открывает день, `/day-close` закрывает. Day Close ≠ Quick Close (Quick Close = сессия, Day Close = день).

## БЛОКИРУЮЩЕЕ: пошаговое исполнение

Day Close = протокол. Исполнять ТОЛЬКО пошагово через TodoWrite.
**Шаг 0 — ПЕРВОЕ действие:** создать список задач прямо сейчас (до любых других действий).
Каждый шаг алгоритма → отдельная задача (pending → in_progress → completed).
Переход к следующему — ТОЛЬКО после отметки текущего. Шаг невозможен → blocked (не пропускать молча).

## Алгоритм

### 0. Extensions (before)

Условие: `params.yaml → day_close_before_enabled: true`. Если `false` → пропустить.
Проверить: `ls extensions/day-close.before.md`. Если существует → `Read` → выполнить как первые шаги.

### 1. Сбор данных

```bash
WORKSPACE_DIR="$(cd "${CLAUDE_SKILL_DIR}/../../../workspaces/CURRENT_WORKSPACE" && pwd)"
for repo in "$WORKSPACE_DIR"/*/; do
  [ -d "$repo/.git" ] || continue
  name=$(basename "$repo")
  commits=$(git -C "$repo" log --since="today 00:00" --oneline --no-merges 2>/dev/null)
  [ -n "$commits" ] && echo "=== $name ===" && echo "$commits"
done
```

Сопоставить коммиты с таблицей «На сегодня» из DayPlan → определить статусы:
- **done** — всё запланированное на день для РП закрыто коммитами
- **partial** — есть коммиты, но не все задачи закрыты
- **not started** — коммитов нет

### 2. Governance batch

**2a.** Обновить WeekPlan (`{{GOVERNANCE_REPO}}/current/Plan W{N}...`): статусы РП. **Grep по номеру РП** — обновить ВСЕ упоминания.

**2b.** Обновить DayPlan `{{GOVERNANCE_REPO}}/current/DayPlan YYYY-MM-DD.md`: статусы ВСЕХ строк (РП + ad-hoc). Done → зачеркнуть.

**2c.** Обновить `{{GOVERNANCE_REPO}}/docs/WP-REGISTRY.md`: статусы + даты.

**2d.** Обновить `{{GOVERNANCE_REPO}}/inbox/open-sessions.log`: удалить строки закрытых сессий.

**2e.** Governance-синхронизация: новые репо/сервисы за день? → REPOSITORY-REGISTRY, navigation.md, MAP.002.

### 3. Архивация и синхронизация MEMORY.md

- Done WP context files → `mv {{GOVERNANCE_REPO}}/inbox/WP-{N}-*.md {{GOVERNANCE_REPO}}/archive/wp-contexts/`
- Done РП → удалить строку из MEMORY.md (они уже зафиксированы в WP-REGISTRY и WeekPlan)

> MEMORY.md хранит ТОЛЬКО активные РП (in_progress + pending). Done = удалить.

### 4. Memory Drift Scan

> Страховочная сетка — ловит то, что не обновили в Quick Close сессий за день.

```bash
grep -nE "→ ждёт|ждёт|dep:|блокер|blocked:|остановлен|ждёт согласования" \
  "$WORKSPACE_DIR/memory/MEMORY.md" 2>/dev/null
```

Для каждого найденного паттерна:
1. Определить номер РП (WP-NNN) из контекста строки
2. Найти WP-context: `ls {{GOVERNANCE_REPO}}/inbox/WP-{N}-*.md` (если заархивирован — `archive/wp-contexts/`)
3. Прочитать секцию «Что узнали» / «Осталось» / финальный статус
4. Если там есть признак закрытия (`DONE`, `РЕШЕНО`, `✅`, `починил`, `закрыт`, `снят`) → обновить MEMORY.md, анонс: *«Memory drift: [факт] устарел → обновлён»*
5. Если WP-context не найден → отметить в итогах: *«Memory drift: WP-N — context не найден, проверить вручную»*

Анонс при 0 изменениях: *«Drift-scan: проверено N паттернов, устаревших фактов не найдено»*

### 5. Index Health Check

> Ловит раздутие индекс-файлов (MEMORY.md, WP-REGISTRY.md, MAPSTRATEGIC.md, *-registry.md, *-index.md, *-catalog.md). Правило: hook-строки в индексах, не дамп контекста.
> **Условный шаг:** если скрипт отсутствует — пропустить.

```bash
SCRIPT="$WORKSPACE_DIR/{{GOVERNANCE_REPO}}/scripts/check-index-health.py"
[ -f "$SCRIPT" ] && python3 "$SCRIPT" || echo "check-index-health.py не установлен — шаг пропущен"
```

Для каждого FAIL/WARN в отчёте:
1. Открыть файл, посмотреть конкретные строки из отчёта.
2. Диагностика: дамп контекста (болезнь) → перенести в source-of-truth; жанр-таблица → пометить `<!-- index-health: skip -->`.
3. Pack-файлы — не чистить автоматически, только пометить skip с обоснованием.

Анонс при 0 WARN/FAIL: *«Index-health: N файлов OK, M skip»*.

### 6. Lesson Hygiene

- Просмотреть секцию «Уроки» в MEMORY.md
- Урок применялся сегодня? → оставить
- Урок не применялся >1 нед и есть в тематическом файле (`lessons_*.md`)? → удалить из MEMORY.md
- Новый урок за день? → записать в MEMORY.md (краткая строка) + тематический файл (подробно)
- Цель: ≤8 уроков в MEMORY.md

### 7. Автоматические шаги (helper script)

Вызвать: `bash "${CLAUDE_SKILL_DIR}/scripts/day-close.sh"`

Это выполнит:
- Backup workspace memory/ (MEMORY.md, day-rhythm-config.yaml и др.) → exocortex/
- Git backup (commit + push memory files, если `GIT_MEMORY_BACKUP=true` в .env)
- Knowledge-MCP reindex (изменённые за день источники)

### 8. Extensions (pre-summary)

Условие: `params.yaml → multiplier_enabled: true`. Если `false` → пропустить.
Проверить: `ls extensions/day-close.multiplier.md`. Если оба условия выполнены → `Read extensions/day-close.multiplier.md` → выполнить.

Алгоритм мультипликатора (из расширения):
- **WakaTime** — физическое время за день
- **Бюджет закрыт** — сумма бюджетов по ВСЕМ РП за день:
  - done → полный бюджет (или пропорционально фазам для зонтичных)
  - partial → % выполнения × бюджет
  - not started → 0h
  - Мелкие РП (бюджет «—» / merged) → 0.25h, не 0
- **Мультипликатор дня** = Бюджет закрыт / WakaTime. Формат: `N.Nx`

Исполнение этого расширения помещает в контекст значение мультипликатора, которое шаг 11 включит в DayPlan.

### 9. Черновик итогов (показать пользователю)

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

### 10. Согласование

Пользователь читает черновик → корректирует → одобряет.

### 11. Запись итогов

**11a.** Найти текущий `DayPlan YYYY-MM-DD.md` в `{{GOVERNANCE_REPO}}/current/`. Если не найден → создать файл `{{GOVERNANCE_REPO}}/current/DayPlan YYYY-MM-DD.md`.

Дописать секцию «Итоги дня» в конец (по шаблону из `persistent-memory/templates-dayplan.md § Шаблон итогов дня`):

- Таблица РП: что сделано / статус
- Коммиты за день
- Мультипликатор IWE (если рассчитан на шаге 8)
- Что нового узнал
- Похвала
- **Завтра начать с:** ВСЕ pending РП — каждый с конкретным next action

**Валидация «Завтра начать с» (ADR-207):** поле не пустое + каждый pending РП упомянут + каждый содержит конкретный next action (не «продолжить работу»).

**11b.** Дописать сводку итогов в WeekPlan:
- Формат: `<details><summary><b>Итоги {день} {дата}</b></summary>...</details>`
- Порядок: свежие итоги СВЕРХУ (обратная хронология)
- Содержание: таблица коммитов по репо, закрытые РП, продвинутые РП, мультипликатор

### 12. Extensions (checks)

Условие: `params.yaml → day_close_checks_enabled: true`. Если `false` → пропустить.
Проверить: `ls extensions/day-close.checks.md`. Если существует → `Read extensions/day-close.checks.md` → выполнить верификацию. БЛОКИРУЮЩЕЕ: commit запрещён до прохождения checks.

### 13. Commit + Push

1. `git add` все изменения (WeekPlan, DayPlan, MEMORY.md, WP-REGISTRY.md, exocortex backup)
2. `git commit -m "day-close: YYYY-MM-DD"`
3. `git push`

**ЗАПРЕЩЕНО коммитить `inbox/fleeting-notes.md`!**

### 14. Compact dashboard

Вывести краткую сводку:

```
Day Close: DD месяца YYYY

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

### 15. Extensions (after)

Условие: `params.yaml → day_close_after_enabled: true`. Если `false` → пропустить.
Проверить: `ls extensions/day-close.after.md`. Если существует → `Read extensions/day-close.after.md` → выполнить содержимое (рефлексия, доп. проверки).

### 16. Верификация (Haiku R23)

> Условный шаг: если `params.yaml → verify_quick_close: false` → пропустить.

Запустить sub-agent Haiku в роли R23 (context isolation). Передать:
- Чеклист Day Close
- DayPlan (секция «Итоги дня»)
- `git diff --name-only HEAD~1`

По ❌ — исправить до завершения.

---

## Чеклист Day Close (для верификатора)

- [ ] Коммиты за день собраны, сопоставлены с DayPlan «На сегодня», статусы определены
- [ ] WeekPlan обновлён (grep по номерам РП — ВСЕ упоминания)
- [ ] DayPlan обновлён (статусы ВСЕХ строк: РП + ad-hoc)
- [ ] WP-REGISTRY.md обновлён (статусы + даты)
- [ ] open-sessions.log: строки закрытых сессий удалены
- [ ] MEMORY.md: done-РП удалены, активные актуальны
- [ ] Drift-scan выполнен (шаг 4)
- [ ] Index Health Check выполнен или пропущен (шаг 5)
- [ ] Lesson Hygiene: уроки MEMORY.md ≤8
- [ ] WP context: done → перемещены в archive/wp-contexts/
- [ ] Backup выполнен (day-close.sh, шаг 7)
- [ ] Мультипликатор IWE рассчитан (если extensions/day-close.multiplier.md существует) или пропущен
- [ ] Черновик итогов показан и согласован с пользователем
- [ ] DayPlan: секция «Итоги дня» записана
- [ ] «Завтра начать с» содержит ВСЕ pending РП с конкретным next action
- [ ] WeekPlan: сводка итогов дописана (details, обратная хронология)
- [ ] Extensions checks пройдены (если есть)
- [ ] Все изменения закоммичены и запушены
- [ ] Governance: REPOSITORY-REGISTRY, navigation.md, MAP.002 (если новые репо/сервисы)

Все ✅ → «День закрыт.» Иначе — указать что осталось.
