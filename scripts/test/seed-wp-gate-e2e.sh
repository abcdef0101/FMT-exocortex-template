#!/usr/bin/env bash
# seed-wp-gate-e2e.sh — workspace для WP Gate E2E: задача вне плана → STOP
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
TARGET="${1:-$(mktemp -d "${ROOT_DIR}/.audit/test-seeds/wp-gate-e2e-XXXXXX")}"
mkdir -p "$TARGET/memory" "$TARGET/DS-strategy/current" "$TARGET/DS-strategy/inbox"

# MEMORY.md — WPs present, "add MCP server" NOT in plan
cat > "$TARGET/memory/MEMORY.md" <<'EOF'
# MEMORY.md
valid_from: 2026-05-01

## РП текущей недели
| # | Название | Статус |
|---|----------|--------|
| 1 | Test coverage | in_progress |
| 2 | CI gates | in_progress |
| 3 | Documentation | done |
EOF

# WeekPlan
cat > "$TARGET/DS-strategy/current/WeekPlan W20 2026.md" <<'EOF'
# WeekPlan W20
## План на неделю
| # | РП | Статус | Бюджет |
|---|-----|--------|--------|
| 1 | Test coverage | in_progress | 8h |
| 2 | CI gates | in_progress | 4h |
| 3 | Documentation | done | 2h |
EOF

# CLAUDE.md (copy from project with WP Gate rules)
cp "$ROOT_DIR/CLAUDE.md" "$TARGET/CLAUDE.md" 2>/dev/null || echo "# CLAUDE.md" > "$TARGET/CLAUDE.md"

# Init git
cd "$TARGET"
git init --quiet 2>/dev/null || true
git add -A >/dev/null 2>&1 || true
git commit -m "seed: WP Gate E2E test" --quiet 2>/dev/null || true

echo "$TARGET"
