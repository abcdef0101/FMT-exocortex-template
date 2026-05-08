#!/usr/bin/env bash
# seed-session-prep.sh — создаёт workspace для Session Prep (headless) E2E
# Usage: bash scripts/test/seed-session-prep.sh [target_dir]
set -euo pipefail

TARGET="${1:-$(mktemp -d -t sessprep-seed-XXXXXX)}"
mkdir -p "$TARGET/DS-strategy/"{current,inbox,docs,archive/week-plans}
mkdir -p "$TARGET/memory"

# Previous WeekPlan (W13 — прошлая неделя, будет архивирован)
cat > "$TARGET/DS-strategy/current/WeekPlan W13 2026.md" <<'EOWP'
# WeekPlan W13 status: confirmed

## План на неделю
| # | РП | Статус | Бюджет |
|---|-----|--------|--------|
| 1 | WP-1 audit tests | done | 8h |
| 2 | WP-2 CI gates | done | 4h |

## Итоги W13
- WP-1 done: 20 findings, 12 fixed
- WP-2 done: ShellCheck + bash -n gates
- Completion rate: 100% (2/2)
EOWP

# Previous DayPlan (будет архивирован)
cat > "$TARGET/DS-strategy/current/DayPlan 2026-03-30.md" <<'EODP'
# Day Plan — 2026-03-30
| # | РП | Статус |
|---|-----|--------|
| 1 | WP-1 audit tests | done |
EODP

# MEMORY.md
cat > "$TARGET/memory/MEMORY.md" <<'EOMEM'
# MEMORY.md
valid_from: 2026-03-24

## РП текущей недели
| # | Название | Статус |
|---|----------|--------|
| 1 | WP-1 audit tests | done |
| 2 | WP-2 CI gates | done |
EOMEM

# Strategy
cat > "$TARGET/DS-strategy/docs/Strategy.md" <<'EOST'
# Strategy
## Приоритеты Q2
- P1: IWE testing coverage ≥80%
- P2: CI pipeline speed
- P3: Documentation quality
EOST

# Dissatisfactions
cat > "$TARGET/DS-strategy/docs/Dissatisfactions.md" <<'EODS'
# Dissatisfactions

| ID | Описание | Статус |
|----|----------|--------|
| NEP1 | Test suite slow | closed — CI improved |
| NEP2 | No ShellCheck locally | active |
EODS

# Inbox: fleeting-notes + WP context + QA report
cat > "$TARGET/DS-strategy/inbox/fleeting-notes.md" <<'EOFN'
# Fleeting Notes
- Нужно ускорить CI пайплайн
- Идея: добавить mutation testing для bash
- Processed: старые заметки из W12
EOFN

cat > "$TARGET/DS-strategy/inbox/WP-1-audit-tests.md" <<'EOWP1'
# WP-1 audit tests
## Осталось
- Статус: done
- Результат: 20 findings → 12 fixed
EOWP1

# Session Agenda
cat > "$TARGET/DS-strategy/docs/Session Agenda.md" <<'EOSA'
# Session Agenda
## Регулярные
- Monday: strategy session
- Daily: day open/close
## Нерегулярные (W14)
- Architecture review: MCP Gateway
- Retro: test coverage audit
EOSA

# Init git
cd "$TARGET"
git init --quiet 2>/dev/null || true
git add -A >/dev/null 2>&1 || true
git commit -m "seed: Session Prep test data" --quiet 2>/dev/null || true

echo "$TARGET"
