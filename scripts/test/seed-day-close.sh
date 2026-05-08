#!/usr/bin/env bash
# seed-day-close.sh — создаёт workspace для Day Close E2E теста
# Usage: bash scripts/test/seed-day-close.sh [target_dir] [date]
# Output: путь к workspace на stdout
set -euo pipefail

TARGET="${1:-$(mktemp -d -t dayclose-seed-XXXXXX)}"
TODAY="${2:-$(date +%Y-%m-%d)}"
YESTERDAY=$(date -d "$TODAY -1 day" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d)

mkdir -p "$TARGET/DS-strategy/"{current,inbox,docs,archive}
mkdir -p "$TARGET/memory"

# DayPlan (today, активный)
cat > "$TARGET/DS-strategy/current/DayPlan $TODAY.md" <<'EOF'
# Day Plan — {{TODAY}}

## План на сегодня
| # | РП | Статус | Бюджет | Результат |
|---|-----|--------|--------|-----------|
| 1 | WP-1 refactor CLI arguments | in_progress | 2h | |
| 2 | WP-2 update documentation | done | 1h | README updated |
| 3 | WP-3 review PR #139 | in_progress | 1h | |

## Календарь
- 09:00-11:00 свободно
- 14:00-15:00 звонок

## Итоги вчера
WP-2 завершён, WP-1 progress

## Pomodoro
work=25 break=5 cycles=4
EOF

# WeekPlan с этой неделей
cat > "$TARGET/DS-strategy/current/WeekPlan W14 2026.md" <<'EOWP'
# WeekPlan W14 (2026-03-30 — 2026-04-05) status: confirmed

## План на неделю
| # | РП | Статус | Бюджет | Репо |
|---|-----|--------|--------|------|
| 1 | WP-1 refactor CLI | in_progress | 8h | FMT |
| 2 | WP-2 update docs | done | 3h | FMT |
| 3 | WP-3 review PR | in_progress | 4h | FMT |
| 4 | WP-4 FPF review | in_progress | 6h | Pack |

## Итоги W13
- WP-5 done, WP-6 done
- carry-over: WP-1 (blocked on API key)

## Повестка
- Обсудить WP-4 scope
- Результаты WP-2
EOWP

# MEMORY.md
cat > "$TARGET/memory/MEMORY.md" <<'EOMEM'
# MEMORY.md
valid_from: 2026-03-30

## РП текущей недели
| # | Название | Статус |
|---|----------|--------|
| 1 | WP-1 refactor CLI | in_progress |
| 2 | WP-2 update docs | done |
| 3 | WP-3 review PR | in_progress |
| 4 | WP-4 FPF review | in_progress |
EOMEM

# WP-REGISTRY
cat > "$TARGET/DS-strategy/docs/WP-REGISTRY.md" <<'EOREG'
# WP Registry

| # | Название | Статус | Активация |
|---|----------|--------|-----------|
| 1 | WP-1 refactor CLI | in_progress | 2026-03-30 |
| 2 | WP-2 update docs | done | 2026-03-28 |
| 3 | WP-3 review PR | in_progress | 2026-04-01 |
| 4 | WP-4 FPF review | in_progress | 2026-04-02 |
EOREG

# fleeting-notes
cat > "$TARGET/DS-strategy/inbox/fleeting-notes.md" <<'EOFN'
# Fleeting Notes
- Processed: WP-2 documentation ready for review
- New: **need to add ShellCheck to CI**
- Pending: WP-4 waiting for Pack access
EOFN

# WP Context files
mkdir -p "$TARGET/DS-strategy/inbox"
cat > "$TARGET/DS-strategy/inbox/WP-1-refactor-cli.md" <<'EOWP1'
# WP-1 refactor CLI

## Осталось (What's Left)
- Что пробовали: extract function approach, broke backward compat
- Что узнали: need to keep old API for 1 release cycle
- Следующий шаг: add deprecation warnings first, then refactor
- Контекст: see ADR-005 for delivery architecture
EOWP1

# previous DayPlan (yesterday)
cat > "$TARGET/DS-strategy/current/DayPlan $YESTERDAY.md" <<'EOYD'
# Day Plan — {{YESTERDAY}}

## План на сегодня
| # | РП | Статус | Бюджет |
|---|-----|--------|--------|
| 1 | WP-1 refactor CLI | in_progress | 2h |
| 2 | WP-2 update docs | done | 1h |

## Итоги дня
- WP-2 done: README.md and SETUP-GUIDE.md updated
- WP-1 progress: identified backward compat issue
- Commits: 3 (all pushed)
- Multiplier: 1.2 (3h closed / 2.5h tracked)
- Praise: WP-2 done ahead of schedule, documentation quality good
- Завтра начать с: WP-1 deprecation warnings, WP-3 review

## Что узнали
- Backward compat: need deprecation cycle → Capture to Pack
EOYD

# Init git
cd "$TARGET"
git init --quiet 2>/dev/null || true
git add -A >/dev/null 2>&1 || true
git commit -m "seed: Day Close test data" --quiet 2>/dev/null || true

echo "$TARGET"
