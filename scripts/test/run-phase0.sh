#!/usr/bin/env bash
# run-phase0.sh — главный раннер тестов Фазы 0 (ADR-005)
# Использование: bash scripts/test/run-phase0.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

export ROOT_DIR

PASS=0
FAIL=0
SKIP=0

echo "========================================="
echo " ADR-005 Phase 0 Integration Tests"
echo "========================================="

for test in "$SCRIPT_DIR"/test-*.sh; do
  tname=$(basename "$test")
  echo ""
  echo "--- $tname ---"

  start_time=$(date +%s%N)

  if bash "$test" > >(while read -r line; do echo "$line"; done) 2>&1; then
    echo "✓ PASS: $tname"
    PASS=$((PASS + 1))
  else
    echo "✗ FAIL: $tname"
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "========================================="
echo " Result: $PASS passed, $FAIL failed, $SKIP skipped"
echo "========================================="

[ "$FAIL" -le 0 ]
