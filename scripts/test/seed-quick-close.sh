#!/usr/bin/env bash
# seed-quick-close.sh — создаёт workspace с активной сессией для Quick Close E2E
# Usage: bash scripts/test/seed-quick-close.sh [target_dir]
set -euo pipefail

TARGET="${1:-$(mktemp -d "${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}/.audit/test-seeds/quick-close-XXXXXX")}"
mkdir -p "$TARGET/DS-strategy/"{inbox,current}
mkdir -p "$TARGET/memory"

# Active WP Context (имитирует середину сессии)
cat > "$TARGET/DS-strategy/inbox/WP-3-review-pr.md" <<'EOWP'
# WP-3 review PR

## Осталось (What's Left)
- Что пробовали: reviewed diff, found 3 issues
- Что узнали: ShellCheck gate is blocking on existing warnings
- Следующий шаг: fix warnings in 2 files, re-request review
- Контекст: PR #139, see .audit/audit-report.md
EOWP

# MEMORY.md с активным РП
cat > "$TARGET/memory/MEMORY.md" <<'EOMEM'
# MEMORY.md
valid_from: 2026-04-01

## РП текущей недели
| # | Название | Статус |
|---|----------|--------|
| 3 | WP-3 review PR | in_progress |
EOMEM

# DayPlan (активный)
cat > "$TARGET/DS-strategy/current/DayPlan 2026-04-02.md" <<'EODP'
# Day Plan — 2026-04-02

## План на сегодня
| # | РП | Статус | Бюджет |
|---|-----|--------|--------|
| 3 | WP-3 review PR | in_progress | 2h |
EODP

# WeekPlan
cat > "$TARGET/DS-strategy/current/WeekPlan W14 2026.md" <<'EOWP'
# WeekPlan W14 (2026-03-30 — 2026-04-05)
| # | РП | Статус | Бюджет |
|---|-----|--------|--------|
| 3 | WP-3 review PR | in_progress | 4h |
EOWP

# Session log (open)
cat > "$TARGET/DS-strategy/inbox/open-sessions.log" <<'EOSL'
2026-04-02 09:15 | WP-3 | claude-sonnet | review PR #139, found ShellCheck issues
EOSL

cd "$TARGET"
git init --quiet 2>/dev/null || true
git add -A >/dev/null 2>&1 || true
git commit -m "seed: Quick Close test data" --quiet 2>/dev/null || true

echo "$TARGET"
