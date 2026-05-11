#!/usr/bin/env bash
# verify-chain-discovery.sh — поиск downstream consumers по изменённым символам
# Собирает affected symbols из git diff и ищет потребителей через grep.
# Использование:
#   bash scripts/verify-chain-discovery.sh [git-diff-args]
#   bash scripts/verify-chain-discovery.sh HEAD~1          # diff с предыдущим коммитом
#   bash scripts/verify-chain-discovery.sh --cached         # staged changes
set -euo pipefail

DIFF_REF="${1:-}"

echo "=== R23 Chain Discovery: поиск downstream consumers ==="

# Собираем изменённые файлы
if [ -n "$DIFF_REF" ]; then
  CHANGED_FILES=$(git diff --name-only "$DIFF_REF" 2>/dev/null || true)
else
  CHANGED_FILES=$(git diff --name-only 2>/dev/null || true)
fi

if [ -z "$CHANGED_FILES" ]; then
  echo "  Нет изменённых файлов."
  exit 0
fi

echo "  Изменённые файлы:"
echo "$CHANGED_FILES" | while read -r f; do echo "    $f"; done

echo ""
echo "  Сбор affected symbols..."

# Извлекаем имена функций/классов/переменных из изменённого diff
SYMBOLS=""
if [ -n "$DIFF_REF" ]; then
  DIFF_OUT=$(git diff "$DIFF_REF" 2>/dev/null || true)
else
  DIFF_OUT=$(git diff 2>/dev/null || true)
fi

# Ищем определения функций в добавленных строках
SYMBOLS=$(echo "$DIFF_OUT" | grep '^+.*\(def \|function \|class \|const \|let \|var \|export \|public \|private \)' | \
  sed -n 's/.*\(def\|function\|class\|const\|let\|var\) \([a-zA-Z_][a-zA-Z0-9_]*\).*/\2/p' | \
  sort -u | head -20)

# Также ищем изменённые функции по изменённому телу
if [ -z "$SYMBOLS" ]; then
  SYMBOLS=$(echo "$DIFF_OUT" | grep '^[+-].*[a-zA-Z_][a-zA-Z0-9_]\{3,\}\s*(' | \
    sed 's/.*\([a-zA-Z_][a-zA-Z0-9_]*\)\s*(.*/\1/' | sort -u | head -20)
fi

if [ -z "$SYMBOLS" ]; then
  echo "  Символы не обнаружены (diff без определений функций)."
  echo "  Используй изменённые файлы как affected scope."
  echo ""
  echo "### AFFECTED FILES (for sub-agent):"
  echo "$CHANGED_FILES"
  echo "### END"
  exit 0
fi

echo "  Обнаруженные символы:"
echo "$SYMBOLS" | while read -r s; do echo "    $s"; done

echo ""
echo "  Поиск downstream consumers..."

# Для каждого символа ищем файлы которые его импортируют/вызывают
echo ""
echo "### DOWNSTREAM CONSUMERS (for sub-agent):"
while read -r symbol; do
  [ -z "$symbol" ] && continue
  CONSUMERS=$(grep -rl "$symbol" --include="*.py" --include="*.ts" --include="*.tsx" --include="*.js" \
    --include="*.sh" --include="*.go" . 2>/dev/null | \
    grep -v -f <(echo "$CHANGED_FILES") | head -10 || true)
  if [ -n "$CONSUMERS" ]; then
    echo "  $symbol →"
    echo "$CONSUMERS" | while read -r c; do echo "    $c"; done
  fi
done <<< "$SYMBOLS"

echo ""
echo "### AFFECTED FILES (for sub-agent):"
echo "$CHANGED_FILES"
echo "### END"
echo ""
echo "✓ Chain discovery завершён."
