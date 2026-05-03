#!/usr/bin/env bash
# run-e2e.sh — главный раннер E2E тестов
# Запускает все скрипты в scripts/test/e2e/ (кроме _lib.sh и SMOKE-TEST.md)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
E2E_DIR="$SCRIPT_DIR/e2e"

export ROOT_DIR

PASS=0
FAIL=0

echo "========================================="
echo " E2E Tests — FMT-exocortex-template"
echo "========================================="

for test in "$E2E_DIR"/e2e-*.sh; do
  tname=$(basename "$test")
  echo ""
  echo "--- $tname ---"

  output=$(bash "$test" 2>&1)
  echo "$output"

  if echo "$output" | grep -q "E2E:.*0 failed"; then
    echo "✓ PASS: $tname"
    PASS=$((PASS + 1))
  else
    echo "✗ FAIL: $tname"
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "========================================="
echo " E2E Result: $PASS passed, $FAIL failed"
echo "========================================="

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Manual smoke tests: scripts/test/e2e/SMOKE-TEST.md"
  exit 1
fi

echo ""
echo "Manual smoke tests: scripts/test/e2e/SMOKE-TEST.md"
exit 0
