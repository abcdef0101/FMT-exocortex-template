#!/usr/bin/env bash
# seed-role-execution-e2e.sh — workspace для Role Execution E2E (strategist morning)
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
TARGET="${1:-$(mktemp -d "${ROOT_DIR}/.audit/test-seeds/role-exec-e2e-XXXXXX")}"
mkdir -p "$TARGET/DS-strategy/current" "$TARGET/DS-strategy/inbox" "$TARGET/memory"

# WeekPlan with active WP
cat > "$TARGET/DS-strategy/current/WeekPlan W20 2026.md" <<'EOF'
# WeekPlan W20
## План на неделю
| # | РП | Статус | Бюджет |
|---|-----|--------|--------|
| 1 | Test coverage | in_progress | 8h |
| 2 | CI gates | done | 4h |
EOF

# Previous DayPlan
cat > "$TARGET/DS-strategy/current/DayPlan 2026-05-07.md" <<'EOF'
# Day Plan — 2026-05-07
## План на сегодня
| # | РП | Статус | Бюджет |
|---|-----|--------|--------|
| 1 | Test coverage | done | 4h |
## Итоги дня
- WP-1: 4 assertions added
- Commits: 2
- Завтра начать с: WP-1 assert scripts
EOF

# MEMORY
cat > "$TARGET/memory/MEMORY.md" <<'EOF'
# MEMORY.md
valid_from: 2026-05-01
## РП текущей недели
| # | Название | Статус |
|---|----------|--------|
| 1 | Test coverage | in_progress |
| 2 | CI gates | done |
EOF

# CLAUDE.md with Day Open rules
cp "$ROOT_DIR/CLAUDE.md" "$TARGET/CLAUDE.md" 2>/dev/null || echo "# CLAUDE.md" > "$TARGET/CLAUDE.md"

# Strategist script symlink
mkdir -p "$TARGET/roles/strategist/scripts"
cp "$ROOT_DIR/roles/strategist/scripts/strategist.sh" "$TARGET/roles/strategist/scripts/strategist.sh" 2>/dev/null || true

cd "$TARGET"
git init --quiet 2>/dev/null || true
git add -A >/dev/null 2>&1 || true
git commit -m "seed: Role Execution E2E test" --quiet 2>/dev/null || true

echo "$TARGET"
