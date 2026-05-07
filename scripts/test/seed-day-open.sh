#!/usr/bin/env bash
# seed-day-open.sh — creates a "Tuesday morning" workspace for Day Open E2E testing
# Usage: bash scripts/test/seed-day-open.sh <target_dir>
# Returns: 0 on success, non-zero on failure
# Requires: GH_TOKEN (optional, for GitHub test repo)
set -euo pipefail

TARGET="${1:-/tmp/iwe-seed-dayopen}"
rm -rf "$TARGET"
mkdir -p "$TARGET"/{docs,current,inbox,archive,memory}

TODAY=$(date +%Y-%m-%d)
# Simulate: today is Tuesday, yesterday is Monday
TUESDAY="${2:-$TODAY}"
MONDAY=$(date -d "$TUESDAY -1 day" +%Y-%m-%d 2>/dev/null || date -d "$TUESDAY -1 day" +%Y-%m-%d)
WEEK_NUM=$(date -d "$TUESDAY" +%V 2>/dev/null || date +%V)
PREV_MONDAY=$(date -d "$MONDAY -7 days" +%Y-%m-%d 2>/dev/null || date -d "$TUESDAY -8 days" +%Y-%m-%d)

FMT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

# =========================================================================
# docs/Strategy.md
# =========================================================================
cat > "$TARGET/docs/Strategy.md" <<'STRATEGY'
---
type: strategy
status: active
created: 2026-01-01
updated: 2026-05-01
review: weekly
---

# Стратегия (тестовый workspace)

> Тестовый документ для Day Open E2E.

<details open>
<summary><b>Фокус: Май 2026</b></summary>

### Состояние
**ТОС-месяца:** IWE testing pipeline 97%+ production readiness.
**Гипотеза:** Day Open automation повысит coverage до 99%.

### Приоритеты месяца
| # | Приоритет | Статус | Бюджет |
|---|----------|--------|--------|
| 1 | IWE testing pipeline | in_progress | ~20h |
| 2 | Day Open E2E | pending | ~10h |
| 3 | Documentation | pending | ~5h |

### Текущие фазы (MAPSTRATEGIC)
| Фаза | Статус | Репо |
|------|--------|------|
| FMT-exocortex-template: testing | in_progress | FMT-exocortex-template |
| DS-strategy: seed data | pending | DS-strategy |

</details>
STRATEGY

# =========================================================================
# docs/Dissatisfactions.md
# =========================================================================
cat > "$TARGET/docs/Dissatisfactions.md" <<'DISSAT'
---
type: doc
status: active
created: 2026-01-01
updated: 2026-05-01
---

# Неудовлетворённости (НЭП)

## Активные

| # | НЭП | Область | Статус | Действие |
|---|-----|---------|--------|----------|
| 1 | Day Open занимает >10 мин ручной работы | DX | active | Автоматизировать headless E2E |
| 2 | Нет тестов для Day Open | Quality | active | Phase 6b: Day Open E2E |
| 3 | fleeting-notes накапливаются без Note Review | Process | active | Nightly note-review |

## Решённые

| # | НЭП | Решение |
|---|-----|---------|
| 4 | Зомби QEMU процессы | -pidfile фикс |
DISSAT

# =========================================================================
# current/WeekPlan W{N}.md (текущая неделя, confirmed)
# =========================================================================
cat > "$TARGET/current/WeekPlan W${WEEK_NUM} ${MONDAY}.md" <<WEEKPLAN
---
type: week-plan
week: W${WEEK_NUM}
date_start: ${MONDAY}
date_end: $(date -d "$MONDAY +6 days" +%Y-%m-%d 2>/dev/null || date -d "$TUESDAY +5 days" +%Y-%m-%d)
status: confirmed
agent: Стратег
---

# WeekPlan W${WEEK_NUM}: ${MONDAY} — $(date -d "$MONDAY +6 days" +%Y-%m-%d 2>/dev/null || date -d "$TUESDAY +5 days" +%Y-%m-%d)

<details open>
<summary><b>План на неделю W${WEEK_NUM}</b></summary>

**Фокус:** Завершить тестирование IWE, начать Day Open E2E.
**Бюджет:** ~28h РП всего / ~35h физ / Плановый мультипликатор ~0.8x

> 🔴 критический 🟡 средний 🟢 низкий

| 🚦 | # | РП | h | Статус | Результат |
|----|---|-----|---|--------|-----------|
| 🔴 | 1 | **Golden image pipeline fixes** — CI integration, pidfile fix | 4h | done | QEMU pidfile fix |
| 🔴 | 2 | **Add Day Open E2E test** — Phase 6b | 8h | in_progress | Day Open test |
| 🟡 | 3 | **Container CI workflow** — Trivy image scan | 6h | done | Container CI |
| 🟡 | 4 | **FPF review findings** — artifact URL fix | 3h | in_progress | FPF artifacts |
| 🔴 | 5 | **VM cleanup pidfile fix** — deploy to CI | 2h | done | VM pidfile |
| 🟢 | 6 | **Update PROCESSES.md** — documentation | 5h | pending | Docs update |

**Сводка:** 6 РП, 28h. 🔴 14h (3) 🟡 9h (2) 🟢 5h (1)

</details>
<details>
<summary><b>Итоги прошлой недели W$((WEEK_NUM - 1))</b></summary>

**Выполнение:** 4/5 РП (80%)
**Перенос:** #3 FPF review findings, #5 VM pidfile fix
**Ключевые выводы:**
- qemu -daemonize double-forks → \$! не ловит настоящий PID
- podman cp ломает симлинки → volume mount лучше

</details>
<details>
<summary><b>Стратегическая сверка</b></summary>

| ID | Результат | Бюджет | Статус | Связанные РП |
|----|-----------|--------|--------|-------------|
| R1 | IWE testing pipeline | 20h | in_progress | WP-1, WP-2 |
| R2 | Day Open E2E | 10h | pending | WP-2 |
| R3 | Documentation | 5h | pending | WP-6 |

**ТОС-месяца:** Production readiness 97%+
**Расхождения:** нет

</details>
<details>
<summary><b>План на ${MONDAY} (понедельник)</b></summary>

| 🚦 | # | РП | h | Результат |
|----|---|-----|---|-----------|
| 🔴 | 1 | **Golden image pipeline fixes** | 2h | done |
| 🔴 | 2 | **Add Day Open E2E test** | 4h | in_progress |
| 🟡 | 4 | **FPF review findings** | 2h | partial |

</details>

*Создан: ${MONDAY} (Strategy Session)*
WEEKPLAN

# =========================================================================
# current/DayPlan (вчера — понедельник, с итогами)
# =========================================================================
cat > "$TARGET/current/DayPlan ${MONDAY}.md" <<DAYPLAN
---
type: daily-plan
date: ${MONDAY}
week: W${WEEK_NUM}
status: done
agent: Стратег
---

# Day Plan: ${MONDAY} (понедельник)

<details open>
<summary><b>План на сегодня</b></summary>

| 🚦 | # | РП | h | Статус | Результат |
|----|---|-----|---|--------|-----------|
| ⚫ | 1 | **Саморазвитие** — Чтение FPF §A | 1 | done | FPF reading |
| 🔴 | 2 | **Golden image pipeline fixes** — pidfile test | 2 | done | pidfile fix |
| 🔴 | 3 | **Add Day Open E2E test** — seed script | 4 | in_progress | seed script draft |
| 🟡 | 4 | **FPF review findings** — artifact URL | 2 | partial | artifact URL research |

**Бюджет дня:** ~9h РП всего / ~8h физ / Плановый мультипликатор ~1.1x

</details>
<details>
<summary><b>Календарь (${MONDAY})</b></summary>

| Время | Событие | Длит. | Связь с РП |
|-------|---------|-------|------------|
| 09:00 | Strategy Session (standup) | 1h | WP-2 |
| 14:00 | Code Review | 1h | — |

⏱ Свободных блоков ≥1h: 10:00-14:00, 15:00-19:00

</details>
<details>
<summary><b>IWE за ночь (светофор)</b></summary>

| Подсистема | Статус | Детали |
|------------|--------|--------|
| Scheduler | 🟢 | Все таймеры активны |
| MCP reindex | 🟢 | Индекс обновлён |
| Scout | 🟡 | 3 находки, 0 review |

</details>
<details>
<summary><b>Разбор заметок</b></summary>

> Все заметки обработаны (Note Review ${MONDAY}, 3 заметки). Carry-over: нет.

</details>
<details>
<summary><b>Итоги вчера</b></summary>

**Коммиты:** 3 в 2 репо | **РП закрыто:** 1

</details>

---

## Итоги дня

| РП | Что сделано | Статус |
|----|-------------|--------|
| #1 | Golden image pipeline fixes — pidfile fix tested | done |
| #3 | Add Day Open E2E test — seed script draft (~60%) | partial |
| #4 | FPF review findings — artifact URL research | partial |

**Коммиты:** 3 в 2 репо (FMT-exocortex-template: 2, DS-strategy: 1)

### Мультипликатор IWE

| Метрика | Значение |
|---------|----------|
| **WakaTime (физическое время)** | 7ч 30мин |
| **Бюджет закрыт (оценки РП)** | ~5h |
| **Мультипликатор дня** | **0.7x** |

**Что нового узнал:** qemu -pidfile надёжнее чем -daemonize; expect setup.sh требует 6 ответов

**Похвала:** pidfile fix работает с первого раза

**Не забыто:** всё чисто

**Завтра начать с:**
1. **WP-4 FPF review findings** — реализовать artifact URL fix, протестировать с реальным репо
2. **WP-2 Add Day Open E2E test** — завершить seed-day-open.sh, начать day-open-test.md

*Закрыто: ${MONDAY} 23:45*
DAYPLAN

# =========================================================================
# memory/MEMORY.md
# =========================================================================
cat > "$TARGET/memory/MEMORY.md" <<'MEMORY'
# Оперативная память (тестовый workspace)

## БЛОКИРУЮЩИЕ

1. WP Gate: любое задание → протокол Открытия → ДО начала работы
2. Push: «заливай» / «запуши» → commit + push без вопросов
3. Close: триггер Закрытия → протокол Закрытия → выполнить

## ВАЖНЫЕ

- Саморазвитие = слот 1, никогда не пропускать
- Capture-to-Pack на каждом рубеже работы

## РП текущей недели

| # | Название | Статус | Класс | Бюджет |
|---|---------|--------|-------|--------|
| 1 | Golden image pipeline fixes | done | closed-loop | 4h |
| 2 | Add Day Open E2E test | in_progress | open-loop | 8h |
| 3 | Container CI workflow | done | closed-loop | 6h |
| 4 | FPF review findings | in_progress | open-loop | 3h |
| 5 | VM cleanup pidfile fix | done | closed-loop | 2h |
| 6 | Update PROCESSES.md | pending | open-loop | 5h |

## Уроки

- qemu -daemonize → -pidfile (2026-05-05)
- expect setup.sh требует 6 ответов (2026-05-05)

## Навигация

| Репо | Назначение |
|------|-----------|
| FMT-exocortex-template | Тестирование, CI |
| DS-strategy | Планы, заметки |
MEMORY

# =========================================================================
# inbox/fleeting-notes.md — 6 заметок разных категорий
# =========================================================================
cat > "$TARGET/inbox/fleeting-notes.md" <<'NOTES'
# fleeting-notes

> Автоматически очищается Note-Review.

## Новые (bold — требуют обработки)

- **Add auto-cleanup for dangling QEMU images older than 24h** — 2026-05-05 (задача)
- **deepseek/deepseek-chat API latency up 30% this week — monitor** — 2026-05-06 (знание)

## 🔄 (идеи без scope)

- "Интеграция с Grafana для дашборда CI метрик" — 2026-05-03 (свежая идея)

## ✅ processed

- "Обновить README после всех изменений" — processed by Note Review 2026-05-05 → РП #6

## Заметки

- 2026-05-05: pidfile fix прошёл все тесты, можно деплоить в CI
- 2026-05-06: нужно обновить coverage matrix в scripts/vm/README.md после Phase 6b
NOTES

# =========================================================================
# inbox/WP-4-fpf-review-findings.md (WP context file)
# =========================================================================
cat > "$TARGET/inbox/WP-4-fpf-review-findings.md" <<'WPCONTEXT'
---
status: in_progress
wp_id: 4
title: FPF review findings
repo: FMT-exocortex-template
created: 2026-05-04
updated: 2026-05-05
---

# WP-4: FPF review findings

## Осталось (What's Left)
- Что пробовали: прямые ссылки на FPF-артефакты в prompts
- Что узнали: artifact URL fix — нужно заменить относительные пути на абсолютные
- Следующий шаг: реализовать artifact URL fix, протестировать с реальным репо
- Контекст: FPF лежит в {{HOME_DIR}}/IWE/FPF, промпты ссылаются на него
WPCONTEXT

# =========================================================================
# inbox/WP-2-add-day-open-e2e.md (WP context file)
# =========================================================================
cat > "$TARGET/inbox/WP-2-add-day-open-e2e.md" <<'WPCONTEXT2'
---
status: in_progress
wp_id: 2
title: Add Day Open E2E test
repo: FMT-exocortex-template
created: 2026-05-05
updated: 2026-05-05
---

# WP-2: Add Day Open E2E test

## Осталось (What's Left)
- Что пробовали: seed-day-open.sh draft (~60%)
- Что узнали: seed должен создавать 10+ файлов для полного состояния "утра вторника"
- Следующий шаг: завершить seed-day-open.sh, начать day-open-test.md
- Контекст: Phase 6b следует паттерну Phase 5b (Generator + Judge)
WPCONTEXT2

# =========================================================================
# inbox/seed-issues.md — тестовые GitHub issues (fallback если gh недоступен)
# =========================================================================
cat > "$TARGET/inbox/seed-issues.md" <<'SEEDISSUES'
# Seed Issues (тестовые — симуляция GitHub issues)

> Используется Day Open если `gh` не аутентифицирован.

## Открытые issues

| # | Repo | Title | Labels | Created |
|---|------|-------|--------|---------|
| 1 | FMT-exocortex-template | Fix CI pipeline timeout | bug | 2026-05-05 |
| 2 | FMT-exocortex-template | Update README for v0.26 | docs | 2026-05-06 |
SEEDISSUES

# =========================================================================
# day-rhythm-config.yaml (минимальный)
# =========================================================================
cat > "$TARGET/memory/day-rhythm-config.yaml" <<'RHYTHM'
interactive: false

budget_spread:
  enabled: true
  threshold_h: 2
  rounding: 0.5

pomodoro:
  work_minutes: 25
  break_minutes: 5
  long_break_cycles: 4

calendar_ids: []

video:
  enabled: false

news:
  enabled: false

mandatory_daily_wps:
  - slug: "fpf-reading"
    title: "Чтение FPF"
    budget: 1h
RHYTHM

# =========================================================================
# archive/.gitkeep
# =========================================================================
touch "$TARGET/archive/.gitkeep"

# =========================================================================
# GitHub test repo (опционально — если есть GH_TOKEN)
# =========================================================================
GITHUB_REPO_CREATED=false
if [ -n "${GH_TOKEN:-}" ] && command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    GITHUB_USER=$(gh api user --jq '.login' 2>/dev/null || echo "")
    if [ -n "$GITHUB_USER" ]; then
      TEST_REPO_NAME="iwe-test-dayopen-$(date +%s)"
      echo "[seed] Creating GitHub test repo: $GITHUB_USER/$TEST_REPO_NAME"
      if gh repo create "$GITHUB_USER/$TEST_REPO_NAME" --private \
        --description "IWE Day Open E2E test (auto-cleanup)" \
        --clone 2>/dev/null; then
        GITHUB_REPO_CREATED=true
        cd "/tmp/$TEST_REPO_NAME" 2>/dev/null || true
        echo "# IWE Day Open E2E Test" > README.md
        git add README.md && git commit -m "init: test repo for Day Open E2E" --quiet 2>/dev/null || true
        git push -u origin main --quiet 2>/dev/null || true

        gh issue create --repo "$GITHUB_USER/$TEST_REPO_NAME" \
          --title "Fix CI pipeline timeout" \
          --body "Phase 4 golden image test times out after 120s on first run." \
          --label bug 2>/dev/null || true
        gh issue create --repo "$GITHUB_USER/$TEST_REPO_NAME" \
          --title "Update README for v0.26" \
          --body "README.md still references v0.25.1 golden image paths." \
          --label docs 2>/dev/null || true

        echo "[seed] GitHub test repo: $GITHUB_USER/$TEST_REPO_NAME"
        echo "IWE_TEST_REPO=$GITHUB_USER/$TEST_REPO_NAME" > "$TARGET/.test-repo.env"
        cd "$TARGET" 2>/dev/null || true
      else
        echo "[seed] WARN: failed to create GitHub test repo (rate limit?)"
      fi
    fi
  fi
fi

if ! $GITHUB_REPO_CREATED; then
  echo "[seed] No GitHub repo created (GH_TOKEN not set or gh unavailable)"
  echo "IWE_TEST_REPO=" > "$TARGET/.test-repo.env"
fi

# =========================================================================
# Create SPOKE: mock WORKPLAN.md in a sibling repo
# =========================================================================
mkdir -p "$TARGET/../DS-agent-workspace"
cat > "$TARGET/../DS-agent-workspace/WORKPLAN.md" <<'SPOKE'
# WORKPLAN: DS-agent-workspace

| # | РП | Статус | Бюджет |
|---|-----|--------|--------|
| 1 | Bot health check | in_progress | 4h |
| 2 | Scheduler refactor | pending | 8h |
SPOKE

# =========================================================================
# Init git in the seeded directory
# =========================================================================
cd "$TARGET"
git init --quiet 2>/dev/null || true
git config user.email "iwe-test@localhost" 2>/dev/null || true
git config user.name "IWE Test" 2>/dev/null || true
git add -A >/dev/null 2>&1 || true
git commit -m "test: seed data for Day Open E2E test" --quiet 2>/dev/null || true

echo "$TARGET"
