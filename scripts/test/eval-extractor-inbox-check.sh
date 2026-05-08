#!/usr/bin/env bash
# eval-extractor-inbox-check.sh — LLM-as-Judge for Extractor inbox-check E2E
set -euo pipefail

if [ -z "${AI_CLI_API_KEY:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  for env_file in "$HOME/.iwe-test-vm/secrets/.env" "$HOME/secrets/.env"; do
    [ -f "$env_file" ] && set -a && source "$env_file" && set +a && break
  done
fi

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUBRICS="$SCRIPT_DIR/rubrics-extractor-inbox-check.yaml"
[ ! -f "$RUBRICS" ] && { echo "ERROR: rubrics not found" >&2; exit 1; }

DS_DIR="$WS_DIR/DS-strategy"
echo "=== LLM-as-Judge: Extractor Inbox Check ==="

JUDGE_PROMPT=$(cat <<PROMPT
Ты — оценщик качества Extractor inbox-check. Оцени классификацию заметок и маршрутизацию знаний по 8 критериям.
Для каждого: score 0.0-1.0, passed (score ≥ threshold), reasoning (1-2 предл, русский).

## Критерии
$(cat "$RUBRICS")

## Входные данные (seed)
=== fleeting-notes.md ===
$(cat "$DS_DIR/inbox/fleeting-notes.md" 2>/dev/null || echo "N/A")
=== captures.md ===
$(cat "$DS_DIR/inbox/captures.md" 2>/dev/null || echo "N/A")
=== CLAUDE.md (routing target) ===
$(head -20 "$WS_DIR/CLAUDE.md" 2>/dev/null || echo "N/A")
=== MEMORY.md ===
$(cat "$WS_DIR/memory/MEMORY.md" 2>/dev/null || echo "N/A")

## Формат ответа — СТРОГО JSON-массив:
[{"metric":"...","score":0.8,"passed":true,"reasoning":"..."},...]
PROMPT
)

export AI_CLI="${AI_CLI_JUDGE:-opencode}"
export AI_CLI_MODEL="${AI_CLI_MODEL_JUDGE:-deepseek/deepseek-chat}"
AI_CLI_TIMEOUT=120

WRAPPER="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts/ai-cli-wrapper.sh"
if [ -f "$WRAPPER" ]; then
  source "$WRAPPER"
  JUDGE_RC=0
  JUDGE_OUT=$(ai_cli_run "$JUDGE_PROMPT" --bare --budget 0.10 2>/dev/null) || JUDGE_RC=$?
  if [ "$JUDGE_RC" -ne 0 ]; then echo "LLM_JUDGE_PASS=0"; echo "LLM_JUDGE_TOTAL=0"; echo "ERROR: LLM call failed" >&2; exit 2; fi
else echo "ERROR: ai-cli-wrapper not found" >&2; exit 1; fi

echo "$JUDGE_OUT" | python3 "$SCRIPT_DIR/_parse_judge_output.py" 2>&1
