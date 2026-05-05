#!/usr/bin/env bash
# seed-strategy-session.sh — creates a minimal DS-strategy workspace for testing
# Usage: source scripts/test/seed-strategy-session.sh <target_dir>
# Output: populates $1 with test DS-strategy structure
# Returns: 0 on success, non-zero on failure
set -euo pipefail

TARGET="${1:-/tmp/iwe-seed-ds-strategy}"
rm -rf "$TARGET"
mkdir -p "$TARGET"/{docs,current,inbox,archive,memory}

TODAY=$(date +%Y-%m-%d)
MONDAY=$(date -d "last monday" +%Y-%m-%d 2>/dev/null || date -d "$TODAY -$(( $(date +%u) - 1 )) days" +%Y-%m-%d)
PREV_MONDAY=$(date -d "$MONDAY -7 days" +%Y-%m-%d)
WEEK_NUM=$(( $(date +%V) ))

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

# Стратегия

> Тестовый документ для headless strategy-session.

<details open>
<summary><b>Фокус: Май 2026</b></summary>

### Состояние
**Факт (W{{PREV_WEEK}}):** Завершены: golden image pipeline, container CI, FPF review.
**ТОС-месяца:** Production readiness 97%+.
**Гипотеза:** Strategy session testing добавит оставшиеся 3%.

### Приоритеты месяца
| # | Приоритет | Статус | Бюджет |
|---|----------|--------|--------|
| 1 | IWE testing pipeline | in_progress | ~20h |
| 2 | Strategy session | pending | ~10h |
| 3 | Documentation | pending | ~5h |

### Текущие фазы (MAPSTRATEGIC)
| Фаза | Статус | Репо |
|------|--------|------|
| FMT-exocortex-template: testing | in_progress | FMT-exocortex-template |
| DS-strategy: seed data | pending | DS-strategy |

</details>
STRATEGY

sed -i "s/{{PREV_WEEK}}/$WEEK_NUM/g" "$TARGET/docs/Strategy.md"

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
| 1 | Тестирование занимает >30 мин | DX | active | Автоматизировать контейнерные тесты |
| 2 | Golden image требует ручной пересборки | Infra | active | qemu-img integrity check (R6) |
| 3 | Нет тестов для стратега | Quality | active | Phase 5: strategy session tests |

## Решённые
| # | НЭП | Решение |
|---|-----|---------|
| 4 | Зомби QEMU процессы | -pidfile фикс |
DISSAT

# =========================================================================
# docs/Session Agenda.md
# =========================================================================
cat > "$TARGET/docs/Session Agenda.md" <<'AGENDA'
---
type: doc
status: active
source: DP.ROLE.012.SC.01
---

# Повестка стратегической сессии

## Типовая сессия

1. Ревью НЭП (5-10 мин)
2. Анализ прошлой недели (15-20 мин)
3. Сдвиг фокуса месяца (10-15 мин)
4. Формирование плана (15-20 мин)
5. Утверждение и синхронизация (5-10 мин)
AGENDA

# =========================================================================
# current/WeekPlan W{N-1}.md (прошлая неделя)
# =========================================================================
cat > "$TARGET/current/WeekPlan W$((WEEK_NUM - 1)) $PREV_MONDAY.md" <<WEEKPLAN
---
type: week-plan
week: W$((WEEK_NUM - 1))
date_start: $PREV_MONDAY
date_end: $MONDAY
status: completed
agent: Стратег
---

# WeekPlan W$((WEEK_NUM - 1)): $PREV_MONDAY — $MONDAY

## Итоги прошлой недели W$((WEEK_NUM - 1))

**Completion rate:** 4/5 РП (80%)

**Carry-over:**
- #5 — FPF review findings (осталось: реализовать #3 artifact URL)
- #3 — Container CI workflow (осталось: Trivy image scan fix)

**Ключевые инсайты:**
- qemu -daemonize double-forks → \$! не ловит настоящий PID
- podman cp ломает симлинки → volume mount лучше но с uid-проблемой

## План на неделю W$((WEEK_NUM - 1))

| # | РП | Бюджет | Статус | Репо |
|---|-----|--------|--------|------|
| 1 | Golden image pipeline fixes | 4h | done | FMT-exocortex-template |
| 2 | Container CI workflow | 6h | done | FMT-exocortex-template |
| 3 | FPF review findings | 3h | in_progress | FMT-exocortex-template |
| 4 | Production readiness R8-R12 | 5h | done | FMT-exocortex-template |
| 5 | VM cleanup pidfile fix | 2h | done | FMT-exocortex-template |

**Бюджет недели:** 20h
WEEKPLAN

# =========================================================================
# inbox/fleeting-notes.md
# =========================================================================
cat > "$TARGET/inbox/fleeting-notes.md" <<'NOTES'
# fleeting-notes

> Автоматически очищается Стратегом при session-prep.

## 🔄 (идеи без scope)
- "Автоматический деплой golden image в CI при пересборке" — 2026-04-28 (висящая >7 дней)
- "Интеграция с Grafana для дашборда CI метрик" — 2026-05-03 (свежая)

## ✅ processed (уже в Pack/РП)
- "R1-R7 production readiness" — processed by strategist 2026-05-04 → РП #4

## Заметки
- 2026-05-05: нужно обновить README после всех изменений
NOTES

# =========================================================================
# inbox/WP-1-golden-image-pipeline.md (WP context file)
# =========================================================================
cat > "$TARGET/inbox/WP-1-golden-image-pipeline.md" <<'WPCONTEXT'
---
status: done
wp_id: 1
title: Golden image pipeline
repo: FMT-exocortex-template
created: 2026-05-01
---

# WP-1: Golden Image Pipeline

## Текущее состояние
Завершён. Все фазы тестов проходят (22/22 → 23/23).
PID-фикс для QEMU применён.

## Решения
- qemu -daemonize double-forks — использовать -pidfile
- podman cp ломает симлинки — использовать git clone
WPCONTEXT

# =========================================================================
# memory/MEMORY.md
# =========================================================================
cat > "$TARGET/memory/MEMORY.md" <<'MEMORY'
# Оперативная память (тестовый workspace)

## РП текущей недели

| # | Название | Статус | Класс | Бюджет |
|---|---------|--------|-------|--------|
| 1 | Golden image pipeline fixes | done | closed-loop | 4h |
| 2 | Container CI workflow | done | closed-loop | 6h |
| 3 | FPF review findings | in_progress | closed-loop | 3h |
| 4 | Production readiness R8-R12 | done | closed-loop | 5h |
| 5 | VM cleanup pidfile fix | done | closed-loop | 2h |

## Записи
- [test-memory](test-memory.md) — тестовая запись
MEMORY

# =========================================================================
# SPOKE: mock WORKPLAN.md in a sibling repo
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
# archive/.gitkeep
# =========================================================================
touch "$TARGET/archive/.gitkeep"

# Init git in the seeded directory (needed for commits)
cd "$TARGET"
git init --quiet 2>/dev/null || true
git config user.email "iwe-test@localhost" 2>/dev/null || true
git config user.name "IWE Test" 2>/dev/null || true
git add -A >/dev/null 2>&1 || true
git commit -m "test: seed data for strategy-session E2E test" --quiet 2>/dev/null || true

echo "$TARGET"
