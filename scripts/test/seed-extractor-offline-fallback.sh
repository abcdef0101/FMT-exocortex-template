#!/usr/bin/env bash
# seed-extractor-offline-fallback.sh — workspace для Extractor offline fallback E2E
# Проверяет: при отсутствии MCP Extractor использует grep/find по локальным PACK-*
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
TARGET="${1:-$(mktemp -d /tmp/iwe-seed-extractor-offline-XXXXXX)}"

# Workspace structure with local Pack (no MCP)
mkdir -p "$TARGET/DS-strategy/inbox" "$TARGET/DS-strategy/inbox/extraction-reports"
mkdir -p "$TARGET/memory"
mkdir -p "$TARGET/PACK-test-domain/pack/test-domain/01-domain-contract"
mkdir -p "$TARGET/PACK-test-domain/pack/test-domain/02-domain-entities"
mkdir -p "$TARGET/PACK-test-domain/pack/test-domain/03-methods"
mkdir -p "$TARGET/roles/extractor/config"

# Pack manifest
cat > "$TARGET/PACK-test-domain/pack/test-domain/00-pack-manifest.md" <<'EOF'
# PACK-test-domain — Test Domain Pack

> **Scope:** Test domain entities and methods for offline fallback verification.
> **Bounded Context:** test-domain

## Contents
- DP.TEST.001 — existing entity (test pattern)
- DP.TEST.M.001 — existing method
EOF

# Existing distinction
cat > "$TARGET/PACK-test-domain/pack/test-domain/01-domain-contract/01B-distinctions.md" <<'EOF'
# Distinctions (test-domain)

## System ≠ Episteme
System = code that executes. Episteme = formalized knowledge.
**Test:** Can it be executed by a machine? Yes → System. No → Episteme.
EOF

# Existing entity — will be the duplicate target
cat > "$TARGET/PACK-test-domain/pack/test-domain/02-domain-entities/TEST.ENTITY.001-test-pattern.md" <<'EOF'
---
id: TEST.ENTITY.001
name: test-pattern
kind: entity
status: active
created: 2026-01-15
---

# Test Pattern (Entity)

A formalized pattern for testing offline fallback behavior.

## Description
This entity describes the standard approach to verifying that MCP-offline fallback
correctly detects duplicates via local filesystem grep instead of knowledge_search.
EOF

# Existing method
cat > "$TARGET/PACK-test-domain/pack/test-domain/03-methods/TEST.M.001-existing-method.md" <<'EOF'
---
id: TEST.M.001
name: existing-method
kind: method
status: active
created: 2026-01-15
---

# Existing Method

## Steps
1. Prepare workspace with local Pack
2. Seed captures including known duplicate
3. Run extraction without MCP
4. Verify duplicate detected via grep fallback
EOF

# Routing table
cat > "$TARGET/roles/extractor/config/routing.md" <<'EOF'
# Маршрутизация знаний

## 1. Pack-репо по домену

| Домен (ключевые слова) | Имя Pack-репо | Короткий префикс (2-3 буквы) | Путь к pack/ директории |
|---|---|---|---|
| test domain, test pattern | PACK-test-domain | TD | PACK-test-domain/pack/test-domain/ |

## 2. Директории по типу знания

| Тип | Код | Директория в Pack | Формат файла |
|-----|-----|-------------------|-------------|
| Доменная сущность | entity | 02-domain-entities/ | Отдельный файл |
| Различение | distinction | 01-domain-contract/01B-distinctions.md | Секция в файле |
| Метод | method | 03-methods/ | Отдельный файл |
EOF

# Captures — includes a DUPLICATE of TEST.ENTITY.001
cat > "$TARGET/DS-strategy/inbox/captures.md" <<'EOF'
# Captures

## Domain Knowledge

### test-pattern (DUPLICATE — exists as TEST.ENTITY.001)
A formalized pattern for testing offline fallback behavior. This is a duplicate
of the existing TEST.ENTITY.001-test-pattern.md entity.

### offline-fallback-design (NEW)
Architecture decision: MCP tools should always have a local filesystem fallback
using grep/find/Read for offline operation.

## Implementation Knowledge

### ai-cli-wrapper: --allowed-tools flag for opencode
The ai-cli-wrapper.sh needs --allowed-tools support for opencode sub-agents.
EOF

# MEMORY.md
cat > "$TARGET/memory/MEMORY.md" <<'EOF'
# MEMORY.md
valid_from: 2026-05-01

## РП текущей недели
| # | Название | Статус |
|---|----------|--------|
| 1 | MCP offline fallback tests | in_progress |

## Lessons
| ID | Урок | Применён |
|----|------|----------|
| L1 | Always provide local fallback for MCP tools | yes |
EOF

# CLAUDE.md
cp "$ROOT_DIR/CLAUDE.md" "$TARGET/CLAUDE.md" 2>/dev/null || echo "# CLAUDE.md placeholder" > "$TARGET/CLAUDE.md"

cd "$TARGET"
git init --quiet 2>/dev/null || true
git add -A >/dev/null 2>&1 || true
git commit -m "seed: extractor offline fallback test" --quiet 2>/dev/null || true

echo "$TARGET"
