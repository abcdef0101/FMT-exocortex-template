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

  local log_dir="/tmp/e2e-ai-${name// /-}-$$"
  mkdir -p "$log_dir"

  # 1. Seed — capture stdout+stderr, take last stdout line for workspace path
  echo "  [seed] $seed..."
  bash "$TEST_DIR/$seed" >"$log_dir/seed.out" 2>"$log_dir/seed.err" && rc=0 || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "  ✗ SEED FAILED (rc=$rc)"
    echo "  seed stderr:"
    [ -s "$log_dir/seed.err" ] && sed 's/^/      /' "$log_dir/seed.err" || echo "      (empty)"
    FAIL=$((FAIL + 1))
    seed_failed=true
    step_failed=true
  else
    WS=$(tail -1 "$log_dir/seed.out")
    if [ -z "$WS" ] || [ ! -d "$WS" ]; then
      echo "  ✗ SEED FAILED (no valid workspace, ws='$WS')"
      echo "  seed stdout (last lines):"
      tail -10 "$log_dir/seed.out" | sed 's/^/      /'
      FAIL=$((FAIL + 1))
      seed_failed=true
      step_failed=true
    fi
  fi

  if ! $seed_failed; then
    if [ -d "$WS" ]; then
      ln -sfn . "$WS/DS-strategy" 2>/dev/null || echo "  - DS-strategy symlink failed (advisory)" >&2
    fi
    echo "  ✓ seed: $WS"

    # 2. Run or Judge (AI process or LLM evaluation)
    if [ -n "$run_flag" ] && [ -f "$TEST_DIR/$eval" ]; then
      case "$run_flag" in
        --run)
          echo "  [run] $eval --run..."
          bash "$TEST_DIR/$eval" "$WS" --run >"$log_dir/run.out" 2>"$log_dir/run.err" && rc=0 || rc=$?
          if [ "$rc" -eq 0 ]; then
            echo "  ✓ run complete"
          else
            echo "  ✗ RUN FAILED (rc=$rc)"
            [ -s "$log_dir/run.err" ] && { echo "  stderr:"; sed 's/^/      /' "$log_dir/run.err"; }
            [ -s "$log_dir/run.out" ] && { echo "  stdout (last 20 lines):"; tail -20 "$log_dir/run.out" | sed 's/^/      /'; }
            FAIL=$((FAIL + 1))
            step_failed=true
          fi
          ;;
        --judge)
          ARTIFACT=$(find "$WS/DS-strategy/current" "$WS/current" -name "DayPlan*" -o -name "WeekPlan*" 2>/dev/null | head -1)
          echo "  [judge] $eval $ARTIFACT..."
          bash "$TEST_DIR/$eval" "$WS" "$ARTIFACT" >"$log_dir/judge.out" 2>"$log_dir/judge.err" && rc=0 || rc=$?
          if [ "$rc" -eq 0 ]; then
            echo "  ✓ judge passed"
          else
            echo "  ✗ JUDGE FAILED (rc=$rc)"
            [ -s "$log_dir/judge.err" ] && { echo "  stderr:"; sed 's/^/      /' "$log_dir/judge.err"; }
            [ -s "$log_dir/judge.out" ] && { echo "  stdout (last 20 lines):"; tail -20 "$log_dir/judge.out" | sed 's/^/      /'; }
            FAIL=$((FAIL + 1))
            step_failed=true
          fi
          ;;
      esac
    fi

    # 3. Assert (structural invariants)
    if [ -f "$TEST_DIR/$assert" ]; then
      echo "  [assert] $assert..."
      bash "$TEST_DIR/$assert" "$WS" >"$log_dir/assert.out" 2>"$log_dir/assert.err" && rc=0 || rc=$?
      if [ "$rc" -eq 0 ]; then
        echo "  ✓ assert passed"
      else
        echo "  ✗ ASSERT FAILED (rc=$rc)"
        [ -s "$log_dir/assert.err" ] && { echo "  stderr:"; sed 's/^/      /' "$log_dir/assert.err"; }
        [ -s "$log_dir/assert.out" ] && { echo "  stdout (last 20 lines):"; tail -20 "$log_dir/assert.out" | sed 's/^/      /'; }
        FAIL=$((FAIL + 1))
        step_failed=true
      fi
    fi
  fi

  if ! $step_failed; then
    PASS=$((PASS + 1))
  fi

  # Cleanup logs on success
  $step_failed && echo "  logs: $log_dir/" || rm -rf "$log_dir"

  echo ""
}

E2E_SCENARIOS=(
  "Day Close|seed-day-close.sh|eval-day-close.sh|assert-day-close.sh"
  "Quick Close|seed-quick-close.sh|eval-quick-close.sh|assert-quick-close.sh"
  "Week Close|seed-week-close.sh|eval-week-close.sh|assert-week-close.sh"
  "wp-new|seed-wp-new.sh|eval-wp-new.sh|assert-wp-new.sh"
  "Day Open|seed-day-open.sh|eval-day-open.sh|assert-day-open.sh"
  "Strategy Session|seed-strategy-session.sh|eval-strategy-session.sh|assert-strategy-session.sh"
  "Session Prep|seed-session-prep.sh|eval-session-prep.sh|assert-session-prep.sh"
  "WP Gate|seed-wp-gate-e2e.sh|eval-wp-gate.sh|assert-wp-gate.sh"
  "ORZ Cycle|seed-orz-cycle.sh|eval-orz-cycle.sh|assert-orz-cycle.sh"
  "Note Review|seed-note-review.sh|eval-note-review.sh|assert-note-review.sh"
  "ArchGate|seed-archgate-e2e.sh|eval-archgate-e2e.sh|assert-archgate.sh"
  "IntegrationGate|seed-integration-gate-e2e.sh|eval-integration-gate-e2e.sh|assert-integration-gate.sh"
  "Role Execution|seed-role-execution-e2e.sh|eval-role-execution-e2e.sh|assert-role-execution.sh"
  "Skill Invocation|seed-skill-invocation-e2e.sh|eval-skill-invocation-e2e.sh|assert-skill-invocation.sh"
  "Extractor Inbox Check|seed-extractor-inbox-check.sh|eval-extractor-inbox-check.sh|assert-extractor-inbox-check.sh"
  "Synchronizer Code Scan|seed-synchronizer-code-scan.sh|eval-synchronizer-code-scan.sh|assert-synchronizer-code-scan.sh"
  "Verifier Pack Entity|seed-verifier-pack-entity.sh|eval-verifier-pack-entity.sh|assert-verifier-pack-entity.sh"
  "Extractor Offline Fallback|seed-extractor-offline-fallback.sh|eval-extractor-offline-fallback.sh|assert-extractor-offline-fallback.sh"
)

run_scenario() {
  local entry="$1"
  local name seed eval_script assert_script
  IFS='|' read -r name seed eval_script assert_script <<< "$entry"
  run_e2e "$name" "$seed" "$eval_script" "$assert_script" "--run"
}

case "$E2E_PHASE" in
  all)
    for entry in "${E2E_SCENARIOS[@]}"; do
      run_scenario "$entry"
    done
    ;;
  *)
    found=false
    for entry in "${E2E_SCENARIOS[@]}"; do
      phase_name=$(echo "$entry" | cut -d'|' -f1 | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
      if [ "$phase_name" = "$E2E_PHASE" ]; then
        run_scenario "$entry"
        found=true
        break
      fi
    done
    if ! $found; then
      echo "ERROR: unknown phase '$E2E_PHASE'"
      echo "Available: all, $(for e in "${E2E_SCENARIOS[@]}"; do echo "$e" | cut -d'|' -f1 | tr '[:upper:]' '[:lower:]' | tr ' ' '-'; done | tr '\n' ' ')"
      exit 1
    fi
    ;;
esac

echo ""
echo "========================================="
echo " E2E Result: $PASS passed, $FAIL failed"
echo "========================================="
[ "$FAIL" -eq 0 ]
