#!/usr/bin/env bash
# seed-synchronizer-code-scan.sh — workspace для Synchronizer code-scan E2E
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
TARGET="${1:-$(mktemp -d /tmp/iwe-seed-sync-scan-XXXXXX)}"
mkdir -p "$TARGET/template" "$TARGET/upstream" "$TARGET/DS-strategy/docs"

# Modified template (simulating drift from upstream)
cat > "$TARGET/template/CLAUDE.md" <<'EOF'
# CLAUDE.md — modified

## Rules
1. set -euo pipefail in all scripts
2. (ADDED LINE — drift detected)
3. Pull before commit
EOF

# Upstream reference (the "golden" version)
cat > "$TARGET/upstream/CLAUDE.md" <<'EOF'
# CLAUDE.md — upstream

## Rules
1. set -euo pipefail in all scripts
2. Pull before commit
EOF

# Modified file with different content
cat > "$TARGET/template/ONTOLOGY.md" <<'EOF'
# ONTOLOGY — modified

Система ≠ Эпистема
Роль ≠ Агент ≠ Инструмент
(DELETED LINE: Верификация ≠ Валидация)
EOF

cat > "$TARGET/upstream/ONTOLOGY.md" <<'EOF'
# ONTOLOGY — upstream

Система ≠ Эпистема
Роль ≠ Агент ≠ Инструмент
Верификация ≠ Валидация
EOF

# Unchanged file (should NOT be flagged)
echo "no changes here" > "$TARGET/template/CHANGELOG.md"
echo "no changes here" > "$TARGET/upstream/CHANGELOG.md"

cd "$TARGET"
git init --quiet 2>/dev/null || true
git add -A >/dev/null 2>&1 || true
git commit -m "seed: synchronizer code-scan test" --quiet 2>/dev/null || true

echo "$TARGET"
