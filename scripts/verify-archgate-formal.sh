#!/usr/bin/env bash
# verify-archgate-formal.sh — механическая проверка ЭМОГССБ-таблицы АрхГейта
# Проверяет формальное соответствие, не качество оценки.
# Использование:
#   bash scripts/verify-archgate-formal.sh [файл с таблицей]
#   echo "$TABLE" | bash scripts/verify-archgate-formal.sh
set -euo pipefail

TABLE_FILE="${1:-}"
PASS=true
FAILED_ITEMS=""

_fail() { PASS=false; FAILED_ITEMS="${FAILED_ITEMS}  - $1"$'\n'; }

if [ -n "$TABLE_FILE" ] && [ -f "$TABLE_FILE" ]; then
  TABLE=$(cat "$TABLE_FILE")
elif [ ! -t 0 ]; then
  TABLE=$(cat)
else
  echo "Использование: verify-archgate-formal.sh [файл] или stdin" >&2
  exit 1
fi

echo "=== R23 Формальная верификация: АрхГейт ==="

# 1. Таблица существует
if [ -z "$TABLE" ]; then
  _fail "ЭМОГССБ-таблица не найдена (пустой ввод или файл)"
  echo "  ✗ ЭМОГССБ-таблица не найдена"
  echo ""
  echo "✗ Верификация НЕ пройдена:"
  echo "$FAILED_ITEMS"
  exit 1
fi
echo "  [1/7] Таблица найдена ✓"

# 2-8. Проверка 7 измерений
DIMS=("Э" "М" "О" "Г" "С" "С2" "Б")
i=1
for dim in "${DIMS[@]}"; do
  i=$((i + 1))
  # Ищем строку с оценкой для измерения (формат: буква | оценка | ... или буква:")
  if echo "$TABLE" | grep -qi "$dim"; then
    echo "  [$i/7] $dim — присутствует ✓"
  else
    _fail "Измерение '$dim' не найдено в таблице"
    echo "  [$i/7] $dim — ОТСУТСТВУЕТ ✗"
  fi
done

# 9. Дата оценки
if echo "$TABLE" | grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}'; then
  echo "  [дата] Дата присутствует ✓"
else
  _fail "Дата оценки не указана (формат YYYY-MM-DD)"
  echo "  [дата] Дата ОТСУТСТВУЕТ ✗"
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
