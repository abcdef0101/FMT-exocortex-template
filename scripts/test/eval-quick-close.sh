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

  QCLOSE_PROMPT="Execute Quick Close (4 steps) in workspace $WS_DIR:

1. Commit + Push: \`cd $WS_DIR && git add -A && git commit -m 'quick-close' && git push\`
2. Update WP Context in $DS_DIR/inbox/ — add '## Осталось' with: что пробовали, что узнали, следующий шаг, контекст, → memory: yes/no
3. KE: route 'Что узнали' — правило→CLAUDE.md, домен→Pack, урок→memory/
4. MEMORY.md: update WP status (in_progress→done)

Files to work with:
- WP Context: $(find "$DS_DIR/inbox" -name "WP-*.md" -type f 2>/dev/null)
- MEMORY.md: $WS_DIR/memory/MEMORY.md
- Session log: $DS_DIR/inbox/open-sessions.log

Read these files, modify them, then commit+push."

  echo "=== Quick Close: running AI process ==="
  AI_CLI_TIMEOUT=300
  export AI_CLI="${AI_CLI:-opencode}"
  export AI_CLI_MODEL="${AI_CLI_MODEL:-deepseek/deepseek-chat}"
  RUN_RC=0
  RUN_OUT=$(ai_cli_run "$QCLOSE_PROMPT" --allowed-tools "Read,Write,Edit,Bash" --budget 0.20 2>/dev/null) || RUN_RC=$?
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
