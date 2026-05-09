#!/usr/bin/env bash
# seed-week-close.sh — создаёт workspace для Week Close E2E теста
# Usage: bash scripts/test/seed-week-close.sh [target_dir]
set -euo pipefail

TARGET="${1:-$(mktemp -d /tmp/iwe-seed-week-close-XXXXXX)}"
mkdir -p "$TARGET/DS-strategy/"{current,inbox,docs,archive}
mkdir -p "$TARGET/memory"

# WeekPlan (текущая неделя, с итогами)
cat > "$TARGET/DS-strategy/current/WeekPlan W14 2026.md" <<'EOWP'
# WeekPlan W14 (2026-03-30 — 2026-04-05) status: confirmed

## План на неделю
| # | РП | Статус | Бюджет | Репо | Результат |
|---|-----|--------|--------|------|----------|
| 1 | WP-1 refactor CLI | done | 8h | FMT | CLI args unified |
| 2 | WP-2 docs | done | 3h | FMT | README + SETUP updated |
| 3 | WP-3 review PR | done | 4h | FMT | #139 approved |
| 4 | WP-4 FPF review | in_progress | 6h | Pack | 3/5 sections done |
| 5 | WP-5 CI gate | done | 2h | FMT | bash -n added |

## Повестка
- Week Close review
- Content plan for W15

## Carry-over
- WP-4 → W15 (remaining 2 sections)
EOWP

# 5 DayPlans (ПН-ПТ)
for i in 1 2 3 4 5; do
  day=$(date -d "2026-03-29 +$i days" +%Y-%m-%d 2>/dev/null || date -v+${i}d -j 202603290000 +%Y-%m-%d)
cat > "$TARGET/DS-strategy/current/DayPlan $day.md" <<EODP
# Day Plan — $day

## План на сегодня
| # | РП | Статус | Бюджет |
|---|-----|--------|--------|
| 1 | WP-$i | done | 2h |

## Итоги дня
- WP-$i done
- Commits: $i
EODP
done

# MEMORY.md
cat > "$TARGET/memory/MEMORY.md" <<'EOMEM'
# MEMORY.md
valid_from: 2026-03-30

## РП текущей недели
| # | Название | Статус |
|---|----------|--------|
| 1 | WP-1 refactor CLI | done |
| 2 | WP-2 docs | done |
| 3 | WP-3 review PR | done |
| 4 | WP-4 FPF review | in_progress |
| 5 | WP-5 CI gate | done |

## Lessons (active)
| ID | Урок | Применён |
|----|------|----------|
| L1 | set -euo pipefail in all bash | yes |
| L2 | test before push | yes |
| L3 | old lesson not applied | no |
EOMEM

# Strategy.md + Dissatisfactions
mkdir -p "$TARGET/DS-strategy/docs"
cat > "$TARGET/DS-strategy/docs/Strategy.md" <<'EOST'
# Strategy

## Приоритеты месяца
- P1: IWE testing coverage
- P2: CLI refactoring
- P3: Documentation
EOST

cat > "$TARGET/DS-strategy/docs/Dissatisfactions.md" <<'EODS'
# Dissatisfactions

| ID | Описание | Статус |
|----|----------|--------|
| NEP1 | Tests too slow | active |
| NEP2 | Docs outdated | closed |
EODS

# Init git
cd "$TARGET"
git init --quiet 2>/dev/null || true
git add -A >/dev/null 2>&1 || true
git commit -m "seed: Week Close test data" --quiet 2>/dev/null || true

echo "$TARGET"
