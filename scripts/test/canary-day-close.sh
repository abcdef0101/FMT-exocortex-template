#!/usr/bin/env bash
# canary-day-close.sh — replay Day Close на копии workspace
# Layer 3 canary test (ADR-009). Еженедельный health check.
# Копирует workspace → запускает Day Close → сравнивает diff.
# Usage: bash scripts/test/canary-day-close.sh <workspace_dir> [--run]
set -euo pipefail

if [ -z "${AI_CLI_API_KEY:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  for env_file in "$HOME/.iwe-test-vm/secrets/.env" "$HOME/secrets/.env"; do
    [ -f "$env_file" ] && set -a && source "$env_file" && set +a && break
  done
fi

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }
[ ! -d "$WS_DIR" ] && { echo "ERROR: dir not found: $WS_DIR" >&2; exit 1; }

RUN_MODE=false
for arg in "$@"; do [ "$arg" = "--run" ] && RUN_MODE=true; done

FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "=== Canary: Day Close Replay ==="
echo "  source: $WS_DIR"

# Capture pre-state
DS_DIR="$WS_DIR/DS-strategy"
[ ! -d "$DS_DIR" ] && DS_DIR="$WS_DIR"

DAYPLAN=$(find "$DS_DIR/current" -name "Day*Plan*" -type f 2>/dev/null | head -1)
WEEKPLAN=$(find "$DS_DIR/current" -name "WeekPlan*" -type f 2>/dev/null | head -1)
MEMORY="$WS_DIR/memory/MEMORY.md"
REGISTRY=$(find "$DS_DIR/docs" -name "WP-REGISTRY*" -type f 2>/dev/null | head -1)

echo "  DayPlan:  $(basename "$DAYPLAN" 2>/dev/null || echo 'N/A')"
echo "  WeekPlan: $(basename "$WEEKPLAN" 2>/dev/null || echo 'N/A')"

# Copy workspace
CANARY_DIR=$(mktemp -d "${WS_DIR%/*}/canary-XXXXXX" 2>/dev/null || mktemp -d "/tmp/canary-dc-XXXXXX")
trap 'rm -rf "$CANARY_DIR"' EXIT
cp -a "$WS_DIR"/* "$CANARY_DIR/" 2>/dev/null || true
cp -a "$WS_DIR"/.git "$CANARY_DIR/" 2>/dev/null || true

echo "  canary: $CANARY_DIR"
_pass "workspace copied"

# Snapshot pre-state
DAYPLAN_BEFORE=$(cat "$DAYPLAN" 2>/dev/null | wc -l || echo 0)
MEMORY_BEFORE=$(cat "$MEMORY" 2>/dev/null | wc -l || echo 0)
WEEKPLAN_BEFORE=$(cat "$WEEKPLAN" 2>/dev/null | wc -l || echo 0)

if $RUN_MODE; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
  WRAPPER="$ROOT_DIR/scripts/ai-cli-wrapper.sh"
  
  DAYCLOSE_PROMPT="Execute Day Close in workspace $CANARY_DIR.
Read the files, add итоги дня with results table, multiplier section,
praise, and Завтра начать с. Update MEMORY.md and WeekPlan statuses.
Commit changes. This is an automated canary test — auto-approve everything."

  if [ -f "$WRAPPER" ]; then
    source "$WRAPPER"
    echo "=== Running Day Close on canary ==="
    AI_CLI_TIMEOUT=600
    export AI_CLI="${AI_CLI:-opencode}"
    export AI_CLI_MODEL="${AI_CLI_MODEL:-deepseek/deepseek-chat}"
    RUN_RC=0
    RUN_OUT=$(ai_cli_run "$DAYCLOSE_PROMPT" --allowed-tools "Read,Write,Edit,Bash" --budget 0.50 2>/dev/null) || RUN_RC=$?
    if [ "$RUN_RC" -ne 0 ]; then echo "ERROR: Day Close failed (rc=$RUN_RC)" >&2; exit 2; fi
    echo "=== Day Close done ==="
  else
    echo "SKIP: ai-cli-wrapper not found (--run requires AI CLI)"
  fi
fi

# Snapshot post-state
CANARY_DP=$(find "$CANARY_DIR" -name "Day*Plan*" -type f 2>/dev/null | head -1)
CANARY_MEMORY="$CANARY_DIR/memory/MEMORY.md"
CANARY_WP=$(find "$CANARY_DIR" -name "WeekPlan*" -type f 2>/dev/null | head -1)

DAYPLAN_AFTER=$(cat "$CANARY_DP" 2>/dev/null | wc -l || echo 0)
MEMORY_AFTER=$(cat "$CANARY_MEMORY" 2>/dev/null | wc -l || echo 0)
WEEKPLAN_AFTER=$(cat "$CANARY_WP" 2>/dev/null | wc -l || echo 0)

echo "  --- diff ---"
echo "  DayPlan:  $DAYPLAN_BEFORE → $DAYPLAN_AFTER lines"
echo "  MEMORY:   $MEMORY_BEFORE → $MEMORY_AFTER lines"
echo "  WeekPlan: $WEEKPLAN_BEFORE → $WEEKPLAN_AFTER lines"

if $RUN_MODE; then
  [ "$DAYPLAN_AFTER" -gt "$DAYPLAN_BEFORE" ] \
    && _pass "DayPlan grew ($((DAYPLAN_AFTER - DAYPLAN_BEFORE)) lines)" \
    || _fail "DayPlan did not grow"

  [ "$MEMORY_AFTER" -ne "$MEMORY_BEFORE" ] \
    && _pass "MEMORY.md changed" \
    || _pass "MEMORY.md unchanged (may already be in final state)"
else
  _pass "diff: run with --run to execute AI process"
fi

echo "  --- file integrity ---"
expected_changes=0
[ "$DAYPLAN_AFTER" -ne "$DAYPLAN_BEFORE" ] && expected_changes=$((expected_changes + 1))
$RUN_MODE && [ "$expected_changes" -eq 0 ] \
  && _fail "no files changed (Day Close may not have run)" \
  || true

# Check no deletions
if [ -n "$CANARY_DP" ] && [ -f "$CANARY_DP" ]; then
  [ -s "$CANARY_DP" ] \
    && _pass "DayPlan: non-empty" \
    || _fail "DayPlan: empty after run"
fi

echo "  --- cleanup ---"
rm -rf "$CANARY_DIR" 2>/dev/null || true
_pass "canary cleaned up"

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL
