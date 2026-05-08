#!/usr/bin/env bash
# run-phase0.sh — главный раннер тестов Фазы 0 (ADR-005)
# Использование: bash scripts/test/run-phase0.sh [--verbose] [--strict]
#   --strict: ShellCheck failures блокируют проход
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

VERBOSE=false
STRICT=false
for arg in "$@"; do
  case "$arg" in
    --verbose|-v) VERBOSE=true ;;
    --strict)     STRICT=true ;;
  esac
done

export ROOT_DIR

PASS=0
FAIL=0
SKIP=0
FAILED_TESTS=()

echo "========================================="
echo " ADR-005 Phase 0 Integration Tests"
echo "========================================="

# === ShellCheck (advisory unless --strict) ===
if command -v shellcheck &>/dev/null; then
  echo ""
  echo "--- ShellCheck (all .sh files) ---"
  SC_FAIL=0
  while IFS= read -r -d '' f; do
    if ! shellcheck -S warning "$f" 2>/dev/null; then
      SC_FAIL=$((SC_FAIL + 1))
      echo "  ✗ $f"
    fi
  done < <(find "$ROOT_DIR" -name "*.sh" -type f -not -path "$ROOT_DIR/workspaces/*" -print0)
  if [ "$SC_FAIL" -eq 0 ]; then
    echo "  ✓ ShellCheck clean"
  elif $STRICT; then
    echo "  ✗ ShellCheck: $SC_FAIL file(s) with warnings"
    echo "  FAIL (--strict mode)"
    exit 1
  else
    echo "  - ShellCheck: $SC_FAIL file(s) with warnings (advisory)"
  fi
else
  echo ""
  echo "--- ShellCheck: not installed (skip) ---"
fi

for test in "$SCRIPT_DIR"/test-*.sh; do
  tname=$(basename "$test")
  echo ""
  echo "--- $tname ---"

  TEST_LOG="/tmp/phase0-${tname}-$$.log"
  if bash "$test" >"$TEST_LOG" 2>&1; then
    if $VERBOSE; then
      cat "$TEST_LOG"
    else
      cat "$TEST_LOG" | grep -E '✓|✗|All tests|passed|failed|FAIL|SKIP|PASS|WARN|•' || cat "$TEST_LOG"
    fi
    echo "✓ PASS: $tname"
    PASS=$((PASS + 1))
  else
    TEST_RC=$?
    echo "✗ FAIL: $tname (rc=$TEST_RC)"
    echo "  >>> Full output of $tname:"
    sed 's/^/  | /' "$TEST_LOG"
    echo "  <<< end of $tname"
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("$tname")
  fi
  rm -f "$TEST_LOG"
done

echo ""
echo "========================================="
echo " Result: $PASS passed, $FAIL failed, $SKIP skipped"
if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo " FAILED TESTS:"
  for ft in "${FAILED_TESTS[@]}"; do
    echo "   - $ft"
  done
fi
echo "========================================="

[ "$FAIL" -le 0 ]
