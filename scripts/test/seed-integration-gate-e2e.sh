#!/usr/bin/env bash
# seed-integration-gate-e2e.sh — workspace для IntegrationGate E2E
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
TARGET="${1:-$(mktemp -d /tmp/iwe-seed-intgate-e2e-XXXXXX)}"
mkdir -p "$TARGET/inbox"

# Intent: user wants to create a new tool
cat > "$TARGET/inbox/new-tool-intent.md" <<'EOF'
# Intent: New MCP Server for Knowledge Indexing

I need to create a new MCP server that indexes all markdown files in the workspace
and provides full-text search via a REST API. The server should run as a background
process and expose search endpoints.
EOF

# CLAUDE.md with IntegrationGate rules
cat > "$TARGET/CLAUDE.md" <<'EOF'
# CLAUDE.md — test workspace

## IntegrationGate (БЛОКИРУЮЩЕЕ)
Новый инструмент/агент/система → проектирование ТОЛЬКО в последовательности:
(1) обещание (Service Clause) → (2) сценарии (мин 3) → (3) роль (DP.ROLE) → (4) реализация.

Прыжок сразу в реализацию = P10 (DP.FM.010).

Исключения (IntegrationGate НЕ нужен):
- Правка существующего инструмента без изменения обещания
- Bugfix без изменения поведения
- Рефакторинг без функциональных изменений
- Экспериментальный скрипт на один запуск

Заголовок реализации: # see DP.SC.NNN, DP.ROLE.NNN
EOF

cd "$TARGET"
git init --quiet 2>/dev/null || true
git add -A >/dev/null 2>&1 || true
git commit -m "seed: IntegrationGate E2E test" --quiet 2>/dev/null || true

echo "$TARGET"
