#!/usr/bin/env bash
# eval-synchronizer-code-scan.sh — LLM-as-Judge for Synchronizer code-scan E2E
set -euo pipefail

if [ -z "${AI_CLI_API_KEY:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  for env_file in "$HOME/.iwe-test-vm/secrets/.env" "$HOME/secrets/.env"; do
    [ -f "$env_file" ] && set -a && source "$env_file" && set +a && break
  done
fi

WS_DIR="${1:-}"
[ -z "$WS_DIR" ] && { echo "ERROR: workspace dir required" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUBRICS="$SCRIPT_DIR/rubrics-synchronizer-code-scan.yaml"
[ ! -f "$RUBRICS" ] && { echo "ERROR: rubrics not found" >&2; exit 1; }

echo "=== LLM-as-Judge: Synchronizer Code Scan ==="

JUDGE_PROMPT=$(cat <<PROMPT
Ты — оценщик качества Synchronizer code-scan. Оцени обнаружение drift между template и upstream по 8 критериям.
Для каждого: score 0.0-1.0, passed (score ≥ threshold), reasoning (1-2 предл, русский).

## Критерии
$(cat "$RUBRICS")

## Модифицированные файлы (template — потенциальный drift)
=== template/CLAUDE.md ===
$(cat "$WS_DIR/template/CLAUDE.md" 2>/dev/null || echo "N/A")
=== upstream/CLAUDE.md ===
$(cat "$WS_DIR/upstream/CLAUDE.md" 2>/dev/null || echo "N/A")

=== template/ONTOLOGY.md ===
$(cat "$WS_DIR/template/ONTOLOGY.md" 2>/dev/null || echo "N/A")
=== upstream/ONTOLOGY.md ===
$(cat "$WS_DIR/upstream/ONTOLOGY.md" 2>/dev/null || echo "N/A")

=== template/CHANGELOG.md ===
$(cat "$WS_DIR/template/CHANGELOG.md" 2>/dev/null || echo "N/A")
=== upstream/CHANGELOG.md ===
$(cat "$WS_DIR/upstream/CHANGELOG.md" 2>/dev/null || echo "N/A")

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
