#!/usr/bin/env bash
# run-e2e-ai.sh — E2E runner: seed → run → assert → judge
# Usage: bash scripts/test/e2e/run-e2e-ai.sh [--phase day-close|all]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$SCRIPT_DIR"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0 FAIL=0 E2E_PHASE="${1:-all}"

run_e2e() {
  local name="$1" seed="$2" eval="$3" assert="$4" run_flag="${5:-}"
  
  echo "========================================="
  echo " E2E: $name"
  echo "========================================="
  
  # 1. Seed
  echo "  [seed] $seed..."
  WS=$(bash "$TEST_DIR/$seed" 2>/dev/null) && rc=0 || rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$WS" ]; then
    echo "  ✗ SEED FAILED"
    FAIL=$((FAIL + 1))
    return
  fi
  [ -d "$WS" ] && ln -sfn . "$WS/DS-strategy" 2>/dev/null || true
  echo "  ✓ seed: $WS"
  
  # 2. Run (AI process — optional)
  if [ -n "$run_flag" ] && [ -f "$TEST_DIR/$eval" ]; then
    echo "  [run] $eval --run..."
    if bash "$TEST_DIR/$eval" "$WS" --run 2>/dev/null; then
      echo "  ✓ run complete"
    else
      echo "  ✗ RUN FAILED"
      FAIL=$((FAIL + 1))
    fi
  fi
  
  # 3. Assert (structural invariants)
  if [ -f "$TEST_DIR/$assert" ]; then
    echo "  [assert] $assert..."
    if bash "$TEST_DIR/$assert" "$WS" 2>/dev/null; then
      echo "  ✓ assert passed"
    else
      echo "  ✗ ASSERT FAILED"
      FAIL=$((FAIL + 1))
    fi
  fi
  
  # 4. Judge (LLM evaluation — already done in eval script, skip here to avoid double billing)
  echo ""
  
  PASS=$((PASS + 1))
}

case "$E2E_PHASE" in
  day-close)
    run_e2e "Day Close" "seed-day-close.sh" "eval-day-close.sh" "assert-day-close.sh" "--run"
    ;;
  quick-close)
    run_e2e "Quick Close" "seed-quick-close.sh" "eval-quick-close.sh" "assert-quick-close.sh" "--run"
    ;;
  week-close)
    run_e2e "Week Close" "seed-week-close.sh" "eval-week-close.sh" "assert-week-close.sh" "--run"
    ;;
  wp-new)
    run_e2e "wp-new" "seed-wp-new.sh" "eval-wp-new.sh" "assert-wp-new.sh" "--run"
    ;;
  all|*)
    run_e2e "Quick Close" "seed-quick-close.sh" "eval-quick-close.sh" "assert-quick-close.sh" "--run"
    run_e2e "wp-new" "seed-wp-new.sh" "eval-wp-new.sh" "assert-wp-new.sh" "--run"
    run_e2e "Day Close" "seed-day-close.sh" "eval-day-close.sh" "assert-day-close.sh" "--run"
    run_e2e "Week Close" "seed-week-close.sh" "eval-week-close.sh" "assert-week-close.sh" "--run"
    ;;
esac

echo ""
echo "========================================="
echo " E2E Result: $PASS passed, $FAIL failed"
echo "========================================="
[ "$FAIL" -eq 0 ]
