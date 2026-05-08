#!/usr/bin/env bash
# eval-quick-close.sh — LLM-as-Judge for Quick Close E2E
# Usage: bash scripts/test/eval-quick-close.sh <workspace_dir> [--run]
set -euo pipefail

if [ -z "${AI_CLI_API_KEY:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  for env_file in "$HOME/.iwe-test-vm/secrets/.env" "$HOME/secrets/.env"; do
    [ -f "$env_file" ] && set -a && source "$env_file" && set +a && break
  done
fi

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }

RUN_MODE=false
for arg in "$@"; do [ "$arg" = "--run" ] && RUN_MODE=true; done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUBRICS="$SCRIPT_DIR/rubrics-quick-close.yaml"
[ ! -f "$RUBRICS" ] && { echo "ERROR: rubrics not found" >&2; exit 1; }
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
WRAPPER="$ROOT_DIR/scripts/ai-cli-wrapper.sh"
DS_DIR="$WS_DIR/DS-strategy"

if $RUN_MODE; then
  [ ! -f "$WRAPPER" ] && { echo "ERROR: ai-cli-wrapper not found" >&2; exit 1; }
  source "$WRAPPER"

  # Use protocol-close.md + --allowed-tools (opencode --agent build has file access)
  PROTOCOL_CLOSE="$ROOT_DIR/persistent-memory/protocol-close.md"
  if [ -f "$PROTOCOL_CLOSE" ]; then
    QCLOSE_PROMPT="$(cat "$PROTOCOL_CLOSE")

---
## Workspace Context (from test harness)
Workspace root: $WS_DIR
DS-strategy directory: $DS_DIR
Active WP Context files: $(find "$DS_DIR/inbox" -name "WP-*.md" -type f 2>/dev/null)
MEMORY.md: $WS_DIR/memory/MEMORY.md
DayPlan: $(find "$DS_DIR/current" -name "Day*Plan*" -type f 2>/dev/null | head -1 || echo "not found")
WeekPlan: $(find "$DS_DIR/current" -name "WeekPlan*" -type f 2>/dev/null | head -1 || echo "not found")
Session log: $DS_DIR/inbox/open-sessions.log

Execute Quick Close (4 steps from protocol-close.md above):
1. Commit + Push all changes
2. Update WP Context file: 'Осталось' with → memory: field
3. KE: route 'Что узнали' to appropriate destination
4. Update MEMORY.md WP status
Read the actual files at the paths listed above — do NOT use embedded content."
  else
    QCLOSE_PROMPT="protocol-close.md not found"
  fi

  echo "=== Quick Close: running AI process ==="
  echo "  prompt: $(wc -l < "$PROTOCOL_CLOSE" 2>/dev/null || echo 0) lines from protocol-close.md"
  AI_CLI_TIMEOUT=600
  export AI_CLI="${AI_CLI:-opencode}"
  export AI_CLI_MODEL="${AI_CLI_MODEL:-deepseek/deepseek-chat}"
  RUN_RC=0
  RUN_OUT=$(ai_cli_run "$QCLOSE_PROMPT" --allowed-tools "Read,Write,Edit,Glob,Grep,Bash" --budget 1.00 2>/dev/null) || RUN_RC=$?
  if [ "$RUN_RC" -ne 0 ]; then echo "ERROR: Quick Close AI failed (rc=$RUN_RC)" >&2; exit 2; fi
  echo "=== Quick Close: AI process done ==="
  if [ "$RUN_RC" -ne 0 ]; then echo "ERROR: Quick Close AI failed (rc=$RUN_RC)" >&2; exit 2; fi
  echo "=== Quick Close: AI process done ==="
fi

echo "=== LLM-as-Judge: Quick Close ==="

JUDGE_PROMPT=$(cat <<PROMPT
Ты — оценщик качества Quick Close. Оцени выполнение 4 шагов по 8 критериям.
Для каждого: score 0.0-1.0, passed (score ≥ threshold), reasoning (1-2 предл, русский).

## Критерии
$(cat "$RUBRICS")

## Состояние после Quick Close
=== WP Context файлы ===
$(find "$DS_DIR/inbox" -name "WP-*.md" 2>/dev/null | while read f; do echo "=== $(basename "$f") ==="; cat "$f"; done)
=== MEMORY.md ===
$(cat "$WS_DIR/memory/MEMORY.md" 2>/dev/null || echo "N/A")
=== WeekPlan ===
$(head -40 "$DS_DIR/current/WeekPlan"*".md" 2>/dev/null || echo "N/A")
=== DayPlan ===
$(head -30 "$DS_DIR/current/DayPlan"*".md" 2>/dev/null || echo "N/A")
=== Session Log ===
$(cat "$DS_DIR/inbox/open-sessions.log" 2>/dev/null || echo "N/A")

## Формат ответа — СТРОГО JSON-массив: [{"metric":"...","score":0.8,"passed":true,"reasoning":"..."},...]
PROMPT
)

export AI_CLI="${AI_CLI_JUDGE:-opencode}"
export AI_CLI_MODEL="${AI_CLI_MODEL_JUDGE:-deepseek/deepseek-chat}"
AI_CLI_TIMEOUT=120

if [ -f "$WRAPPER" ]; then
  source "$WRAPPER"
  JUDGE_RC=0
  JUDGE_OUT=$(ai_cli_run "$JUDGE_PROMPT" --bare --budget 0.10 2>/dev/null) || JUDGE_RC=$?
  if [ "$JUDGE_RC" -ne 0 ]; then echo "LLM_JUDGE_PASS=0"; echo "LLM_JUDGE_TOTAL=0"; echo "ERROR: LLM call failed" >&2; exit 2; fi
else echo "ERROR: ai-cli-wrapper not found" >&2; exit 1; fi

echo "$JUDGE_OUT" | python3 "$SCRIPT_DIR/_parse_judge_output.py" 2>&1
