#!/usr/bin/env bash
# seed-extractor-inbox-check.sh — workspace для Extractor inbox-check E2E
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
TARGET="${1:-$(mktemp -d "${ROOT_DIR}/.audit/test-seeds/extractor-inbox-XXXXXX")}"
mkdir -p "$TARGET/DS-strategy/inbox" "$TARGET/memory"

# fleeting-notes.md — 7 notes of different types for classification
cat > "$TARGET/DS-strategy/inbox/fleeting-notes.md" <<'EOF'
# Fleeting Notes

## Bold (новые — требуют классификации)

**Тесты ролей всё ещё без E2E покрытия, нужно добавить smoke-тесты**
Критический пробел в качестве — роли не проверяются автоматически.

**НЭП: CI пайплайн занимает 5 минут на пустой коммит**
Это замедляет разработку, нужно профилировать шаги.

**Идея поста: как мы покрыли тестами 46 production-скриптов за 3 дня**
Можно в клубный канал, тема актуальная.

**just random thought about weather today**
Не относится к работе, просто заметка.

## 🔄 (идеи без scope)
- "Интеграция с Grafana для CI метрик" — висит с 2026-04-20 (>7 дней!)

## Processed
- ~~Добавить ShellCheck в CI~~ — done W15
EOF

# inbox/captures.md — pre-captured knowledge
cat > "$TARGET/DS-strategy/inbox/captures.md" <<'EOF'
# Captures

## Domain Knowledge
- DP.FM.010: прыжок в реализацию без IntegrationGate = антипаттерн

## Implementation Knowledge
- ai-cli-wrapper.sh: opencode --agent build для --allowed-tools
EOF

# MEMORY.md with active WPs
cat > "$TARGET/memory/MEMORY.md" <<'EOF'
# MEMORY.md
valid_from: 2026-05-01

## РП текущей недели
| # | Название | Статус |
|---|----------|--------|
| 1 | Role coverage tests | in_progress |

## Lessons
| ID | Урок | Применён |
|----|------|----------|
| L1 | set -euo pipefail in all tests | yes |
EOF

# Provide CLAUDE.md as routing target
cp "$ROOT_DIR/CLAUDE.md" "$TARGET/CLAUDE.md" 2>/dev/null || echo "# CLAUDE.md placeholder" > "$TARGET/CLAUDE.md"

cd "$TARGET"
git init --quiet 2>/dev/null || true
git add -A >/dev/null 2>&1 || true
git commit -m "seed: extractor inbox-check test" --quiet 2>/dev/null || true

echo "$TARGET"
