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
  
  local seed_failed=false
  local step_failed=false

  # 1. Seed — take last line only (seed scripts may print info to stdout)
  echo "  [seed] $seed..."
  WS=$(bash "$TEST_DIR/$seed" 2>/dev/null | tail -1) && rc=0 || rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$WS" ] || [ ! -d "$WS" ]; then
    echo "  ✗ SEED FAILED (ws='$WS')"
    FAIL=$((FAIL + 1))
    seed_failed=true
    step_failed=true
  fi

  if ! $seed_failed; then
    [ -d "$WS" ] && ln -sfn . "$WS/DS-strategy" 2>/dev/null || true
    echo "  ✓ seed: $WS"

    # 2. Run or Judge (AI process or LLM evaluation)
    if [ -n "$run_flag" ] && [ -f "$TEST_DIR/$eval" ]; then
      case "$run_flag" in
        --run)
          echo "  [run] $eval --run..."
          if bash "$TEST_DIR/$eval" "$WS" --run 2>/dev/null; then
            echo "  ✓ run complete"
          else
            echo "  ✗ RUN FAILED"
            FAIL=$((FAIL + 1))
            step_failed=true
          fi
          ;;
        --judge)
          ARTIFACT=$(find "$WS/DS-strategy/current" "$WS/current" -name "DayPlan*" -o -name "WeekPlan*" 2>/dev/null | head -1)
          echo "  [judge] $eval $ARTIFACT..."
          if bash "$TEST_DIR/$eval" "$WS" "$ARTIFACT" 2>/dev/null; then
            echo "  ✓ judge passed"
          else
            echo "  ✗ JUDGE FAILED"
            FAIL=$((FAIL + 1))
            step_failed=true
          fi
          ;;
      esac
    fi

    # 3. Assert (structural invariants)
    if [ -f "$TEST_DIR/$assert" ]; then
      echo "  [assert] $assert..."
      if bash "$TEST_DIR/$assert" "$WS" 2>/dev/null; then
        echo "  ✓ assert passed"
      else
        echo "  ✗ ASSERT FAILED"
        FAIL=$((FAIL + 1))
        step_failed=true
      fi
    fi
  fi

  if ! $step_failed; then
    PASS=$((PASS + 1))
  fi

  echo ""
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
  day-open)
    run_e2e "Day Open" "seed-day-open.sh" "eval-day-open.sh" "assert-day-open.sh" "--run"
    ;;
  strategy-session)
    run_e2e "Strategy Session" "seed-strategy-session.sh" "eval-strategy-session.sh" "assert-strategy-session.sh" "--run"
    ;;
  session-prep)
    run_e2e "Session Prep" "seed-session-prep.sh" "eval-session-prep.sh" "assert-session-prep.sh" "--run"
    ;;
  wp-gate)
    run_e2e "WP Gate" "seed-wp-gate-e2e.sh" "eval-wp-gate.sh" "assert-wp-gate.sh" "--run"
    ;;
  orz-cycle)
    run_e2e "ORZ Cycle" "seed-orz-cycle.sh" "eval-orz-cycle.sh" "assert-orz-cycle.sh" "--run"
    ;;
  note-review)
    run_e2e "Note Review" "seed-note-review.sh" "eval-note-review.sh" "assert-note-review.sh" "--run"
    ;;
  archgate)
    run_e2e "ArchGate" "seed-archgate-e2e.sh" "eval-archgate-e2e.sh" "assert-archgate.sh" "--run"
    ;;
  intgate)
    run_e2e "IntegrationGate" "seed-integration-gate-e2e.sh" "eval-integration-gate-e2e.sh" "assert-integration-gate.sh" "--run"
    ;;
  role-exec)
    run_e2e "Role Execution" "seed-role-execution-e2e.sh" "eval-role-execution-e2e.sh" "assert-role-execution.sh" "--run"
    ;;
  skill-invoke)
    run_e2e "Skill Invocation" "seed-skill-invocation-e2e.sh" "eval-skill-invocation-e2e.sh" "assert-skill-invocation.sh" "--run"
    ;;
  extractor)
    run_e2e "Extractor Inbox Check" "seed-extractor-inbox-check.sh" "eval-extractor-inbox-check.sh" "assert-extractor-inbox-check.sh" "--run"
    ;;
  synchronizer)
    run_e2e "Synchronizer Code Scan" "seed-synchronizer-code-scan.sh" "eval-synchronizer-code-scan.sh" "assert-synchronizer-code-scan.sh" "--run"
    ;;
  verifier)
    run_e2e "Verifier Pack Entity" "seed-verifier-pack-entity.sh" "eval-verifier-pack-entity.sh" "assert-verifier-pack-entity.sh" "--run"
    ;;
  offline-fallback)
    run_e2e "Extractor Offline Fallback" "seed-extractor-offline-fallback.sh" "eval-extractor-offline-fallback.sh" "assert-extractor-offline-fallback.sh" "--run"
    ;;
  all|*)
    run_e2e "Quick Close" "seed-quick-close.sh" "eval-quick-close.sh" "assert-quick-close.sh" "--run"
    run_e2e "wp-new" "seed-wp-new.sh" "eval-wp-new.sh" "assert-wp-new.sh" "--run"
    run_e2e "Day Close" "seed-day-close.sh" "eval-day-close.sh" "assert-day-close.sh" "--run"
    run_e2e "Week Close" "seed-week-close.sh" "eval-week-close.sh" "assert-week-close.sh" "--run"
    run_e2e "Day Open" "seed-day-open.sh" "eval-day-open.sh" "assert-day-open.sh" "--run"
    run_e2e "Strategy Session" "seed-strategy-session.sh" "eval-strategy-session.sh" "assert-strategy-session.sh" "--run"
    run_e2e "Session Prep" "seed-session-prep.sh" "eval-session-prep.sh" "assert-session-prep.sh" "--run"
    run_e2e "WP Gate" "seed-wp-gate-e2e.sh" "eval-wp-gate.sh" "assert-wp-gate.sh" "--run"
    run_e2e "ORZ Cycle" "seed-orz-cycle.sh" "eval-orz-cycle.sh" "assert-orz-cycle.sh" "--run"
    run_e2e "Note Review" "seed-note-review.sh" "eval-note-review.sh" "assert-note-review.sh" "--run"
    run_e2e "ArchGate" "seed-archgate-e2e.sh" "eval-archgate-e2e.sh" "assert-archgate.sh" "--run"
    run_e2e "IntegrationGate" "seed-integration-gate-e2e.sh" "eval-integration-gate-e2e.sh" "assert-integration-gate.sh" "--run"
    run_e2e "Role Execution" "seed-role-execution-e2e.sh" "eval-role-execution-e2e.sh" "assert-role-execution.sh" "--run"
    run_e2e "Skill Invocation" "seed-skill-invocation-e2e.sh" "eval-skill-invocation-e2e.sh" "assert-skill-invocation.sh" "--run"
    run_e2e "Extractor Inbox Check" "seed-extractor-inbox-check.sh" "eval-extractor-inbox-check.sh" "assert-extractor-inbox-check.sh" "--run"
    run_e2e "Synchronizer Code Scan" "seed-synchronizer-code-scan.sh" "eval-synchronizer-code-scan.sh" "assert-synchronizer-code-scan.sh" "--run"
    run_e2e "Verifier Pack Entity" "seed-verifier-pack-entity.sh" "eval-verifier-pack-entity.sh" "assert-verifier-pack-entity.sh" "--run"
    run_e2e "Extractor Offline Fallback" "seed-extractor-offline-fallback.sh" "eval-extractor-offline-fallback.sh" "assert-extractor-offline-fallback.sh" "--run"
    ;;
esac

echo ""
echo "========================================="
echo " E2E Result: $PASS passed, $FAIL failed"
echo "========================================="
[ "$FAIL" -eq 0 ]
