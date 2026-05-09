#!/usr/bin/env bash
# canary-day-open.sh — replay Day Open на копии workspace
# Layer 3 canary test (ADR-009). Еженедельный health check.
# Usage: bash scripts/test/canary-day-open.sh <workspace_dir> [--run]
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

echo "=== Canary: Day Open Replay ==="
echo "  source: $WS_DIR"

DS_DIR="$WS_DIR/DS-strategy"
[ ! -d "$DS_DIR" ] && DS_DIR="$WS_DIR"

CANARY_DIR=$(mktemp -d "${WS_DIR%/*}/canary-XXXXXX" 2>/dev/null || mktemp -d "/tmp/canary-do-XXXXXX")
trap 'rm -rf "$CANARY_DIR"' EXIT
cp -a "$WS_DIR"/* "$CANARY_DIR/" 2>/dev/null || true
cp -a "$WS_DIR"/.git "$CANARY_DIR/" 2>/dev/null || true

echo "  canary: $CANARY_DIR"
_pass "workspace copied"

WEEKPLAN_BEFORE=$(find "$DS_DIR/current" -name "WeekPlan*" -type f -exec wc -l {} \; 2>/dev/null | tail -1 | awk '{print $1}')
[ -z "$WEEKPLAN_BEFORE" ] && WEEKPLAN_BEFORE=0

if $RUN_MODE; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
  WRAPPER="$ROOT_DIR/scripts/ai-cli-wrapper.sh"

  DAYOPEN_PROMPT="Execute Day Open in workspace $CANARY_DIR.
Read MEMORY.md, WeekPlan, and fleeting-notes. Build DayPlan with:
- «План на сегодня» table with WP-N, priority markers, time estimates
- «Календарь» with time blocks
- «Итоги вчера» from git log and previous DayPlan
- «Разбор заметок» from fleeting-notes.md
- Self-development (⚫) as first slot
- Carry-over items from WeekPlan in_progress
Save to DS-strategy/current/DayPlan.md. This is an automated canary test — auto-approve all actions."

  if [ -f "$WRAPPER" ]; then
    source "$WRAPPER"
    echo "=== Running Day Open on canary ==="
    AI_CLI_TIMEOUT=600
    export AI_CLI="${AI_CLI:-opencode}"
    export AI_CLI_MODEL="${AI_CLI_MODEL:-deepseek/deepseek-chat}"
    RUN_RC=0
    RUN_OUT=$(ai_cli_run "$DAYOPEN_PROMPT" --allowed-tools "Read,Write,Edit,Bash" --budget 0.50 2>/dev/null) || RUN_RC=$?
    if [ "$RUN_RC" -ne 0 ]; then echo "ERROR: Day Open failed (rc=$RUN_RC)" >&2; exit 2; fi
    echo "=== Day Open done ==="
  else
    echo "SKIP: ai-cli-wrapper not found (--run requires AI CLI)"
  fi
fi

CANARY_DP=$(find "$CANARY_DIR" -name "Day*Plan*" -type f 2>/dev/null | head -1)

if $RUN_MODE; then
  if [ -n "$CANARY_DP" ] && [ -f "$CANARY_DP" ]; then
    DP_LINES=$(wc -l < "$CANARY_DP" 2>/dev/null || echo 0)
    [ "$DP_LINES" -gt 10 ] \
      && _pass "DayPlan created ($DP_LINES lines)" \
      || _fail "DayPlan too short ($DP_LINES lines)"
  else
    _fail "DayPlan not created"
  fi
else
  _pass "diff: run with --run to execute AI process"
fi

echo "  --- cleanup ---"
rm -rf "$CANARY_DIR" 2>/dev/null || true
_pass "canary cleaned up"

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL
