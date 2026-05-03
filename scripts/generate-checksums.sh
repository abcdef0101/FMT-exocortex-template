#!/usr/bin/env bash
# generate-checksums.sh — генерирует checksums.yaml с SHA-256 хешами платформенных файлов
# Запускается при релизе для актуализации checksums.yaml
# ADR-005 §2

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$ROOT_DIR/checksums.yaml"

# Файлы для checksum — платформенные, не NEVER-TOUCH
PLATFORM_DIRS=(
  "CLAUDE.md"
  "persistent-memory"
  ".claude/skills"
  ".claude/rules"
  ".claude/hooks"
  "roles"
  "scripts"
  "seed/manifest.yaml"
  "seed/CLAUDE.md"
  "seed/.mcp.json"
  "seed/.gitignore"
  "seed/extensions"
  "extension-points.yaml"
  "CHANGELOG.md"
  "ONTOLOGY.md"
  "params.yaml"
)

# NEVER-TOUCH: файлы, которые update.sh не проверяет и не перезаписывает
NEVER_TOUCH=(
  "seed/MEMORY.md"
  "seed/params.yaml"
  "seed/day-rhythm-config.yaml"
  "seed/settings.local.json"
  "workspaces/"
  "extensions/"
)

# Нормализация перед хешированием
normalize() {
  sed 's/[[:space:]]*$//' "$1"  # strip trailing whitespace
}

echo "Generating checksums..."

cat > "$OUTPUT" << 'HEADER'
# Checksums — SHA-256 хеши платформенных файлов
# Генерируется: scripts/generate-checksums.sh
# ADR-005 §2: checksum-based enforcement при update.sh --apply

HEADER

echo "version: $(date +%Y.%m.%d)" >> "$OUTPUT"
echo "generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$OUTPUT"

echo "" >> "$OUTPUT"
echo "never_touch:" >> "$OUTPUT"
for nt in "${NEVER_TOUCH[@]}"; do
  echo "  - $nt" >> "$OUTPUT"
done

echo "" >> "$OUTPUT"
echo "files:" >> "$OUTPUT"

for dir in "${PLATFORM_DIRS[@]}"; do
  if [ -f "$ROOT_DIR/$dir" ]; then
    # Single file
    sha=$(normalize "$ROOT_DIR/$dir" | sha256sum | cut -d' ' -f1)
    echo "  $dir: \"$sha\"" >> "$OUTPUT"
    echo "  ✓ $dir"
  elif [ -d "$ROOT_DIR/$dir" ]; then
    # Directory — recurse
    while IFS= read -r -d '' file; do
      rel="${file#$ROOT_DIR/}"
      # Skip directories, non-files
      [ -f "$file" ] || continue
      sha=$(normalize "$file" | sha256sum | cut -d' ' -f1)
      echo "  $rel: \"$sha\"" >> "$OUTPUT"
    done < <(find "$ROOT_DIR/$dir" -type f -print0 | sort -z)
    echo "  ✓ $dir/ ($(find "$ROOT_DIR/$dir" -type f | wc -l) files)"
  fi
done

echo ""
echo "Done: $OUTPUT"
