#!/usr/bin/env bash
# verify-adversarial-scope.sh — поиск непрочитанных файлов для adversarial review
# Сравнивает git diff --stat с явно переданным списком прочитанных файлов.
# Использование:
#   bash scripts/verify-adversarial-scope.sh [read-files-list]
#   bash scripts/verify-adversarial-scope.sh "file1.ts file2.ts"  # список прочитанных
#   bash scripts/verify-adversarial-scope.sh --from-session         # читать из транскрипта
set -euo pipefail

READ_INPUT="${1:-}"
FROM_SESSION=false
[ "$READ_INPUT" = "--from-session" ] && FROM_SESSION=true

echo "=== R23 Adversarial Scope Discovery ==="

# 1. Собираем изменённые файлы
CHANGED=$(git diff --stat --name-only 2>/dev/null | head -50 || true)
CHANGED_CACHED=$(git diff --cached --stat --name-only 2>/dev/null | head -50 || true)
ALL_CHANGED=$(echo -e "${CHANGED}\n${CHANGED_CACHED}" | sort -u | grep -v '^$' || true)

if [ -z "$ALL_CHANGED" ]; then
  echo "  Нет изменённых файлов."
  exit 0
fi

echo "  Изменённые файлы ($(echo "$ALL_CHANGED" | wc -l)):"
echo "$ALL_CHANGED" | while read -r f; do echo "    $f"; done

# 2. Собираем прочитанные файлы
if [ "$FROM_SESSION" = true ]; then
  echo ""
  echo "  Поиск прочитанных файлов из скрипта не поддерживается."
  echo "  Передай список прочитанных файлов аргументом."
  echo ""
  echo "### UNREAD FILES (все изменённые — для ручной проверки):"
  echo "$ALL_CHANGED"
  echo "### END"
  exit 0
fi

READ_FILES="${READ_INPUT}"
if [ -z "$READ_FILES" ]; then
  echo ""
  echo "  Список прочитанных файлов не передан."
  echo ""
  echo "### UNREAD FILES (все изменённые):"
  echo "$ALL_CHANGED"
  echo "### END"
  exit 0
fi

# 3. Вычисляем разницу
UNREAD=""
while read -r f; do
  [ -z "$f" ] && continue
  if ! echo "$READ_FILES" | grep -qF "$f" 2>/dev/null; then
    UNREAD="${UNREAD}${f}"$'\n'
  fi
done <<< "$ALL_CHANGED"

UNREAD=$(echo "$UNREAD" | grep -v '^$' || true)

echo ""
echo "  Прочитанные файлы: $(echo "$READ_FILES" | wc -w)"
echo "  Непрочитанные файлы: $(echo "$UNREAD" | wc -l)"

echo ""
echo "### UNREAD FILES (for sub-agent):"
if [ -n "$UNREAD" ]; then
  echo "$UNREAD" | while read -r f; do echo "  $f"; done
else
  echo "  (все изменённые файлы прочитаны)"
fi
echo ""
echo "### AFFECTED FILES (for sub-agent):"
echo "$ALL_CHANGED" | while read -r f; do echo "  $f"; done
echo "### END"

# 4. Проверка scope claim
if [ -n "$UNREAD" ]; then
  CHANGED_COUNT=$(echo "$ALL_CHANGED" | wc -l)
  UNREAD_COUNT=$(echo "$UNREAD" | wc -l)
  READ_COUNT=$((CHANGED_COUNT - UNREAD_COUNT))
  echo ""
  echo "  Scope coverage: $READ_COUNT/$CHANGED_COUNT файлов прочитано ($(( READ_COUNT * 100 / CHANGED_COUNT ))%)"
fi

echo ""
echo "✓ Adversarial scope discovery завершён."
