#!/usr/bin/env bash
# seed-orz-cycle.sh — workspace для полного цикла ОРЗ: open → work → close
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
TARGET="${1:-$(mktemp -d "${ROOT_DIR}/.audit/test-seeds/orz-cycle-XXXXXX")}"
mkdir -p "$TARGET/memory" "$TARGET/DS-strategy/current" "$TARGET/DS-strategy/inbox" "$TARGET/DS-strategy/docs"

# MEMORY.md with active WP
cat > "$TARGET/memory/MEMORY.md" <<'EOF'
# MEMORY.md
valid_from: 2026-05-08

## РП текущей недели
| # | Название | Статус |
|---|----------|--------|
| 1 | ORZ test cycle | in_progress |
EOF

# WeekPlan
cat > "$TARGET/DS-strategy/current/WeekPlan W20 2026.md" <<'EOF'
# WeekPlan W20
## План на неделю
| # | РП | Статус | Бюджет |
|---|-----|--------|--------|
| 1 | ORZ test cycle | in_progress | 2h |
EOF

# DayPlan
cat > "$TARGET/DS-strategy/current/DayPlan 2026-05-08.md" <<'EOF'
# Day Plan — 2026-05-08

## План на сегодня
| # | РП | Статус | Бюджет |
|---|-----|--------|--------|
| 1 | ORZ test cycle | in_progress | 2h |
EOF

# WP Context (active)
cat > "$TARGET/DS-strategy/inbox/WP-1-orz-test-cycle.md" <<'EOF'
# WP-1 ORZ test cycle

## Осталось (What's Left)
- Что пробовали: seed workspace created
- Что узнали: ORZ protocol triggers on every task
- Следующий шаг: run full cycle test
- Контекст: ADR-009 testing strategy
→ memory: no
EOF

# CLAUDE.md
cp "$ROOT_DIR/CLAUDE.md" "$TARGET/CLAUDE.md" 2>/dev/null || echo "# CLAUDE.md" > "$TARGET/CLAUDE.md"

# Init git
cd "$TARGET"
git init --quiet 2>/dev/null || true
git add -A >/dev/null 2>&1 || true
git commit -m "seed: ORZ cycle test" --quiet 2>/dev/null || true

echo "$TARGET"
