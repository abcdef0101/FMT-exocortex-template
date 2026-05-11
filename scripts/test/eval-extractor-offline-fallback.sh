#!/usr/bin/env bash
# eval-extractor-offline-fallback.sh — AI runner + LLM-as-Judge for Extractor offline fallback E2E
# Usage: bash scripts/test/eval-extractor-offline-fallback.sh <workspace_dir> [--run]
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
[ ! -d "$WS_DIR" ] && { echo "ERROR: dir not found: $WS_DIR" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if $RUN_MODE; then
  WRAPPER="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts/ai-cli-wrapper.sh"
  [ -f "$WRAPPER" ] || { echo "ERROR: ai-cli-wrapper not found" >&2; exit 1; }
  source "$WRAPPER"

  EXTRACTOR_PROMPT=$(cat <<'PROMPT'
Ты — R2 Экстрактор. Выполни проверку дублей и маршрутизацию captures.

Рабочее пространство: __WS_DIR__

ВАЖНО:
- MCP knowledge-сервер НЕ подключён. knowledge_search недоступен.
- Используй ТОЛЬКО локальный fallback: grep/find/Read по __WS_DIR__/PACK-*/pack/
- Маршрутизацию бери из __WS_DIR__/roles/extractor/config/routing.md

Шаги:
1. Прочитай __WS_DIR__/DS-strategy/inbox/captures.md
2. Прочитай __WS_DIR__/roles/extractor/config/routing.md — таблицу маршрутизации
3. Для каждого доменного кандидата:
   a. Определи целевой Pack по routing.md
   b. Проверь дубли: grep по ключевым терминам кандидата в __WS_DIR__/PACK-*/pack/
   c. Если дубликат найден → reject, укажи существующий файл
   d. Если не дубликат → accept, предложи маршрут в Pack
4. Implementation-кандидаты → DS docs/
5. Запиши extraction report в __WS_DIR__/DS-strategy/inbox/extraction-reports/offline-fallback-report.md

Формат отчёта (строго):
```markdown
# Extraction Report: Offline Fallback Test

## Метод проверки
MCP недоступен — использован локальный grep/find по PACK-*/pack/

## Кандидаты

### 1. test-pattern
- **Тип:** domain
- **Проверка:** grep -ri "test pattern" __WS_DIR__/PACK-*/pack/
- **Результат:** reject — дубликат
- **Существующий файл:** [путь к TEST.ENTITY.001]
- **Обоснование:** [почему дубликат]

### 2. offline-fallback-design
- **Тип:** domain
- **Проверка:** grep -ri "offline fallback" __WS_DIR__/PACK-*/pack/
- **Результат:** accept
- **Маршрут:** PACK-test-domain/pack/test-domain/02-domain-entities/
- **Обоснование:** [почему новый]

### 3. ai-cli-wrapper
- **Тип:** implementation
- **Результат:** accept
- **Маршрут:** DS docs/
- **Обоснование:** implementation knowledge
```

Отвечай ТОЛЬКО на русском.
PROMPT
)
  EXTRACTOR_PROMPT="${EXTRACTOR_PROMPT//__WS_DIR__/$WS_DIR}"

  echo "=== Extractor Offline Fallback ==="
  export AI_CLI="${AI_CLI:-opencode}"
  export AI_CLI_MODEL="${AI_CLI_MODEL:-deepseek/deepseek-chat}"
  AI_CLI_TIMEOUT=300
  export WORKSPACE_DIR="$WS_DIR"
  ai_cli_run "$EXTRACTOR_PROMPT" --allowed-tools "Read,Write,Edit,Glob,Grep,Bash" --budget 0.30 2>/dev/null || { echo "ERROR: Extractor run failed" >&2; exit 2; }
  [ -f "$WS_DIR/DS-strategy/inbox/extraction-reports/offline-fallback-report.md" ] \
    || { echo "ERROR: extraction report not created by AI" >&2; exit 3; }
  echo "=== Extractor Offline Fallback: done ==="
fi

# LLM-as-Judge: score the result (only when report exists)
REPORT_FILE=$(find "$WS_DIR/DS-strategy/inbox/extraction-reports" -name "offline-fallback-report.md" 2>/dev/null | head -1)
if [ -f "$REPORT_FILE" ]; then
  echo "=== LLM-as-Judge: Extractor Offline Fallback ==="
else
  echo "=== LLM-as-Judge: skipped (no extraction report) ==="
  echo "LLM_JUDGE_PASS=0"
  echo "LLM_JUDGE_TOTAL=0"
  exit 0
fi

RUBRICS="$SCRIPT_DIR/rubrics-extractor-offline-fallback.yaml"
[ ! -f "$RUBRICS" ] && { echo "ERROR: rubrics not found" >&2; exit 1; }

CAPTURES_FILE="$WS_DIR/DS-strategy/inbox/captures.md"

JUDGE_PROMPT=$(cat <<PROMPT
Ты — оценщик качества Extractor offline fallback. Оцени extraction report по 6 критериям.
Для каждого: score 0.0-1.0, passed (score ≥ threshold), reasoning (1-2 предл, русский).

## Критерии
$(cat "$RUBRICS")

## Входные данные
=== extraction report ===
$(cat "${REPORT_FILE:-N/A}" 2>/dev/null || echo "N/A")
=== captures ===
$(cat "${CAPTURES_FILE:-N/A}" 2>/dev/null || echo "N/A")
=== routing.md ===
$(cat "$WS_DIR/roles/extractor/config/routing.md" 2>/dev/null || echo "N/A")

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
