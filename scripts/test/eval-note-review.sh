#!/usr/bin/env bash
# eval-note-review.sh — LLM-as-Judge for Note Review E2E
# Usage: bash scripts/test/eval-note-review.sh <workspace_dir> [--run]
set -euo pipefail

if [ -z "${AI_CLI_API_KEY:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  for env_file in "$HOME/.iwe-test-vm/secrets/.env" "$HOME/secrets/.env"; do
    [ -f "$env_file" ] && set -a && source "$env_file" && set +a && break
  done
fi

RUN_MODE=false
for arg in "$@"; do [ "$arg" = "--run" ] && RUN_MODE=true; done

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }

if $RUN_MODE; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  WRAPPER="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts/ai-cli-wrapper.sh"
  [ -f "$WRAPPER" ] || { echo "ERROR: ai-cli-wrapper not found" >&2; exit 1; }
  source "$WRAPPER"
  NOTE_PROMPT="Execute Note Review in workspace $WS_DIR.
Read fleeting-notes.md. Classify each note into: НЭП, Задача, Domain Knowledge,
Implementation, Draft, Personal Data, Noise.
Write proposals to Dissatisfactions, WeekPlan, captures.md, draft-list.
Archive processed notes. This is automated test — auto-approve."
  AI_CLI_TIMEOUT=300
  export AI_CLI="${AI_CLI:-opencode}"
  export AI_CLI_MODEL="${AI_CLI_MODEL:-deepseek/deepseek-chat}"
  ai_cli_run "$NOTE_PROMPT" --allowed-tools "Read,Write,Edit,Bash" --budget 0.30 2>/dev/null || { echo "ERROR: Note Review AI failed" >&2; exit 2; }
fi

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUBRICS="$SCRIPT_DIR/rubrics-note-review.yaml"
[ ! -f "$RUBRICS" ] && { echo "ERROR: rubrics not found" >&2; exit 1; }

DS_DIR="$WS_DIR/DS-strategy"
echo "=== LLM-as-Judge: Note Review ==="

JUDGE_PROMPT=$(cat <<PROMPT
Ты — оценщик качества Note Review. Оцени классификацию заметок по 8 критериям.
Для каждого: score 0.0-1.0, passed (score ≥ threshold), reasoning (1-2 предл, русский).

## Критерии
$(cat "$RUBRICS")

## Заметки для классификации
=== fleeting-notes.md ===
$(cat "$DS_DIR/inbox/fleeting-notes.md" 2>/dev/null || echo "N/A")

## Контекст
=== Strategy.md ===
$(cat "$DS_DIR/docs/Strategy.md" 2>/dev/null || echo "N/A")
=== Dissatisfactions.md ===
$(cat "$DS_DIR/docs/Dissatisfactions.md" 2>/dev/null || echo "N/A")
=== WeekPlan ===
$(cat "$DS_DIR/current/WeekPlan"*".md" 2>/dev/null || echo "N/A")

## Формат ответа — СТРОГО JSON-массив:
[{"metric":"...","score":0.8,"passed":true,"reasoning":"..."},...]
PROMPT
)

AI_CLI_JUDGE="${AI_CLI_JUDGE:-${AI_CLI:-opencode}}"
export AI_CLI="$AI_CLI_JUDGE"
export AI_CLI_MODEL="${AI_CLI_MODEL_JUDGE:-deepseek/deepseek-chat}"
AI_CLI_TIMEOUT=120

WRAPPER="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts/ai-cli-wrapper.sh"
if [ -f "$WRAPPER" ]; then
  source "$WRAPPER"
  JUDGE_RC=0
  JUDGE_OUT=$(ai_cli_run "$JUDGE_PROMPT" --bare --budget 0.10 2>/dev/null) || JUDGE_RC=$?
  if [ "$JUDGE_RC" -ne 0 ]; then echo "LLM_JUDGE_PASS=0"; echo "LLM_JUDGE_TOTAL=0"; echo "ERROR: LLM call failed (rc=$JUDGE_RC)" >&2; exit 2; fi
else
  echo "ERROR: ai-cli-wrapper.sh not found" >&2; exit 1
fi

echo "$JUDGE_OUT" | python3 "$SCRIPT_DIR/_parse_judge_output.py" 2>&1
