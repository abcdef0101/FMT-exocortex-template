#!/usr/bin/env bash
# verify-capture-formal.sh — механическая проверка capture-candidate
# Проверяет формальное соответствие, не качество содержания.
# Использование:
#   bash scripts/verify-capture-formal.sh <candidate-file> [manifest-file]
set -euo pipefail

CANDIDATE="${1:-}"
MANIFEST="${2:-}"
PASS=true
FAILED_ITEMS=""

_fail() { PASS=false; FAILED_ITEMS="${FAILED_ITEMS}  - $1"$'\n'; }

if [ -z "$CANDIDATE" ] || [ ! -f "$CANDIDATE" ]; then
  echo "Использование: verify-capture-formal.sh <candidate.md> [manifest.yaml]" >&2
  exit 2
fi

echo "=== R23 Формальная верификация: Capture ==="

# 1. Файл существует и не пустой
if [ ! -s "$CANDIDATE" ]; then
  _fail "Candidate-файл пуст: $CANDIDATE"
else
  echo "  [1/5] Файл существует и не пуст ✓"
fi

# 2. Frontmatter с name/description
if head -1 "$CANDIDATE" | grep -q '^---$'; then
  if grep -q '^name:\|^title:' "$CANDIDATE" 2>/dev/null; then
    echo "  [2/5] Frontmatter: name/title присутствует ✓"
  else
    _fail "Frontmatter без name/title"
    echo "  [2/5] Frontmatter: name/title ОТСУТСТВУЕТ ✗"
  fi
  if grep -q '^description:\|^summary:' "$CANDIDATE" 2>/dev/null; then
    echo "  [3/5] Frontmatter: description присутствует ✓"
  else
    _fail "Frontmatter без description"
    echo "  [3/5] Frontmatter: description ОТСУТСТВУЕТ ✗"
  fi
else
  _fail "Нет YAML frontmatter (файл не начинается с ---)"
  echo "  [2/5] Frontmatter ОТСУТСТВУЕТ ✗"
fi

# 3. Есть тело контента после frontmatter
if grep -q '^---$' "$CANDIDATE" 2>/dev/null; then
  BODY_START=$(grep -n '^---$' "$CANDIDATE" | tail -1 | cut -d: -f1)
  TOTAL_LINES=$(wc -l < "$CANDIDATE")
  if [ "$BODY_START" -lt "$TOTAL_LINES" ]; then
    echo "  [4/5] Тело контента присутствует ✓"
  else
    _fail "Тело контента пустое (только frontmatter)"
    echo "  [4/5] Тело контента ПУСТОЕ ✗"
  fi
fi

# 4. Проверка ссылок на существующие файлы (если manifest)
if [ -n "$MANIFEST" ] && [ -f "$MANIFEST" ]; then
  echo "  [5/5] Ссылки из manifest — проверяем..."
  if command -v yq >/dev/null 2>&1; then
    yq -r '.sources[]?.path // empty' "$MANIFEST" 2>/dev/null | while read -r path; do
      [ -f "$path" ] || _fail "Ссылка из manifest на несуществующий файл: $path"
    done
  else
    echo "    ~ yq не найден, пропускаем проверку ссылок manifest"
  fi
else
  echo "  [5/5] Manifest не указан — пропускаем проверку ссылок ✓"
fi

echo ""
if [ "$PASS" = true ]; then
  echo "✓ Формальная верификация пройдена."
  exit 0
else
  echo "✗ Формальная верификация НЕ пройдена:"
  echo "$FAILED_ITEMS"
  exit 1
fi
