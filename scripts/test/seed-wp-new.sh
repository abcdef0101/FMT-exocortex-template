#!/usr/bin/env bash
# seed-wp-new.sh — создаёт workspace БЕЗ нового РП для wp-new E2E теста
# Usage: bash scripts/test/seed-wp-new.sh [target_dir]
set -euo pipefail

TARGET="${1:-$(mktemp -d /tmp/iwe-seed-wp-new-XXXXXX)}"
mkdir -p "$TARGET/DS-strategy/"{current,inbox,docs}
mkdir -p "$TARGET/memory"

# WP-REGISTRY (без WP-5)
cat > "$TARGET/DS-strategy/docs/WP-REGISTRY.md" <<'EOREG'
# WP Registry

| # | Название | Статус | Активация |
|---|----------|--------|-----------|
| 1 | WP-1 refactor CLI | done | 2026-03-30 |
| 2 | WP-2 update docs | done | 2026-03-28 |
| 3 | WP-3 review PR | done | 2026-04-01 |
| 4 | WP-4 add test coverage | in_progress | 2026-04-03 |
EOREG

# MEMORY.md (без WP-5)
cat > "$TARGET/memory/MEMORY.md" <<'EOMEM'
# MEMORY.md
valid_from: 2026-04-03

## РП текущей недели
| # | Название | Статус |
|---|----------|--------|
| 4 | WP-4 add test coverage | in_progress |
EOMEM

# WeekPlan (без WP-5)
cat > "$TARGET/DS-strategy/current/WeekPlan W14 2026.md" <<'EOWP'
# WeekPlan W14 (2026-03-30 — 2026-04-05) status: confirmed

## План на неделю
| # | РП | Статус | Бюджет |
|---|-----|--------|--------|
| 4 | WP-4 add test coverage | in_progress | 6h |

## Повестка
- WP-4 status
EOWP

# DayPlan (активный, без WP-5)
cat > "$TARGET/DS-strategy/current/DayPlan 2026-04-03.md" <<'EODP'
# Day Plan — 2026-04-03

## План на сегодня
| # | РП | Статус | Бюджет |
|---|-----|--------|--------|
| 4 | WP-4 add test coverage | in_progress | 3h |
EODP

# Strategy
mkdir -p "$TARGET/DS-strategy/docs"
cat > "$TARGET/DS-strategy/docs/Strategy.md" <<'EOST'
# Strategy
## Приоритеты
- P1: Test coverage → нужен WP-5 на CI gates
EOST

# Init git
cd "$TARGET"
git init --quiet 2>/dev/null || true
git add -A >/dev/null 2>&1 || true
git commit -m "seed: wp-new test data (before WP-5 creation)" --quiet 2>/dev/null || true

echo "$TARGET"
