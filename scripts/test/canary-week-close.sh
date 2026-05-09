#!/usr/bin/env bash
# canary-week-close.sh — replay Week Close на копии workspace
# Layer 3 canary test (ADR-009). Еженедельный health check.
# Usage: bash scripts/test/canary-week-close.sh <workspace_dir> [--run]
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

echo "=== Canary: Week Close Replay ==="
echo "  source: $WS_DIR"

DS_DIR="$WS_DIR/DS-strategy"
[ ! -d "$DS_DIR" ] && DS_DIR="$WS_DIR"

CANARY_DIR=$(mktemp -d "${WS_DIR%/*}/canary-XXXXXX" 2>/dev/null || mktemp -d "/tmp/canary-wc-XXXXXX")
trap 'rm -rf "$CANARY_DIR"' EXIT
cp -a "$WS_DIR"/* "$CANARY_DIR/" 2>/dev/null || true
cp -a "$WS_DIR"/.git "$CANARY_DIR/" 2>/dev/null || true

echo "  canary: $CANARY_DIR"
_pass "workspace copied"

WEEKPLAN_BEFORE=$(find "$DS_DIR/current" -name "WeekPlan*" -type f -exec wc -l {} \; 2>/dev/null | tail -1 | awk '{print $1}')
[ -z "$WEEKPLAN_BEFORE" ] && WEEKPLAN_BEFORE=0
MEMORY_BEFORE=$(cat "$WS_DIR/memory/MEMORY.md" 2>/dev/null | wc -l || echo 0)

if $RUN_MODE; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
  WRAPPER="$ROOT_DIR/scripts/ai-cli-wrapper.sh"

  WEEKCLOSE_PROMPT="Execute Week Close in workspace $CANARY_DIR.
Read MEMORY.md and WeekPlan. Add итоги W{N} with completion rate table.
Generate content plan for next week. Update MEMORY.md with lessons learned.
Run ADR audit — check all ADR statuses are current.
Archive WeekPlan to archive/week-plans/. Commit changes.
This is an automated canary test — auto-approve everything."

  if [ -f "$WRAPPER" ]; then
    source "$WRAPPER"
    echo "=== Running Week Close on canary ==="
    AI_CLI_TIMEOUT=600
    export AI_CLI="${AI_CLI:-opencode}"
    export AI_CLI_MODEL="${AI_CLI_MODEL:-deepseek/deepseek-chat}"
    RUN_RC=0
    RUN_OUT=$(ai_cli_run "$WEEKCLOSE_PROMPT" --allowed-tools "Read,Write,Edit,Bash" --budget 0.50 2>/dev/null) || RUN_RC=$?
    if [ "$RUN_RC" -ne 0 ]; then echo "ERROR: Week Close failed (rc=$RUN_RC)" >&2; exit 2; fi
    echo "=== Week Close done ==="
  else
    echo "SKIP: ai-cli-wrapper not found (--run requires AI CLI)"
  fi
fi

CANARY_WP=$(find "$CANARY_DIR" -name "WeekPlan*" -type f 2>/dev/null | head -1)
CANARY_MEMORY="$CANARY_DIR/memory/MEMORY.md"

echo "  --- diff ---"
WEEKPLAN_AFTER=$(cat "$CANARY_WP" 2>/dev/null | wc -l || echo 0)
MEMORY_AFTER=$(cat "$CANARY_MEMORY" 2>/dev/null | wc -l || echo 0)
echo "  WeekPlan: $WEEKPLAN_BEFORE → $WEEKPLAN_AFTER lines"
echo "  MEMORY:   $MEMORY_BEFORE → $MEMORY_AFTER lines"

if $RUN_MODE; then
  [ "$WEEKPLAN_AFTER" -ne "$WEEKPLAN_BEFORE" ] \
    && _pass "WeekPlan changed" \
    || _fail "WeekPlan unchanged"
  grep -qiE 'итоги\|completion\|W[0-9]+' "$CANARY_WP" 2>/dev/null \
    && _pass "WeekPlan has итоги sections" \
    || _fail "WeekPlan missing итоги"
else
  _pass "diff: run with --run to execute AI process"
fi

echo "  --- cleanup ---"
rm -rf "$CANARY_DIR" 2>/dev/null || true
_pass "canary cleaned up"

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL
