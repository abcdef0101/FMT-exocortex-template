#!/usr/bin/env bash
# create-agents.sh — генерация sub-agent definition файлов из model-tiers.yaml
# Для Claude Code: генерит .claude/agents/*.md
# Для OpenCode: генерит .opencode/agents/*.md
# Использование:
#   bash scripts/create-agents.sh              # оба формата
#   bash scripts/create-agents.sh --claude     # только Claude Code
#   bash scripts/create-agents.sh --opencode   # только OpenCode
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATES_DIR="$ROOT_DIR/seed/agents/templates"

# Список агентов: имя и тир
AGENTS=(
  "verifier-code:thinking"
  "verifier-archgate:pro"
  "verifier-capture:thinking"
  "verifier-chain:thinking"
  "verifier-adversarial:thinking"
)

MODE="${1:-all}"

resolve_model_for_tier() {
  local tier="$1"
  bash "$SCRIPT_DIR/ai-cli-wrapper.sh" resolve "$tier" 2>/dev/null || echo "ERROR: cannot resolve tier $tier"
}

generate_agents() {
  local format="$1"  # claude или opencode
  local out_dir=""

  case "$format" in
    claude)   out_dir="$ROOT_DIR/.claude/agents" ;;
    opencode) out_dir="$ROOT_DIR/.opencode/agents" ;;
    *) echo "ERROR: unknown format $format" >&2; return 1 ;;
  esac

  mkdir -p "$out_dir"

  for entry in "${AGENTS[@]}"; do
    local name="${entry%%:*}"
    local tier="${entry##*:}"
    local template="$TEMPLATES_DIR/${name}.${format}.md"
    local output="$out_dir/${name}.md"

    if [ ! -f "$template" ]; then
      echo "  WARN: шаблон не найден: $template"
      continue
    fi

    local model_id
    if [ "$format" = "claude" ]; then
      # Claude Code: используем короткие алиасы (haiku/sonnet/opus) если возможно
      # или полный Anthropic model ID
      case "$tier" in
        fast)     model_id="haiku" ;;
        thinking) model_id="sonnet" ;;
        pro)      model_id="opus" ;;
        *)        model_id=$(resolve_model_for_tier "$tier") ;;
      esac
    else
      model_id=$(resolve_model_for_tier "$tier")
    fi

    if [ -z "$model_id" ] || echo "$model_id" | grep -q "ERROR"; then
      echo "  ERROR: не удалось резолвить модель для tier=$tier"
      continue
    fi

    sed "s|{{MODEL}}|${model_id}|g" "$template" > "$output"
    echo "  ✓ $format: $name (tier=$tier, model=$model_id)"
  done
}

echo "=== Генерация sub-agent definition файлов ==="

# Резолвим модель для Claude Code (Anthropic) и OpenCode отдельно
# Примечание: Claude Code использует алиасы (haiku/sonnet/opus),
# OpenCode использует полные provider/model ID из model-tiers.yaml

if [ "$MODE" = "all" ] || [ "$MODE" = "--claude" ]; then
  echo ""
  echo "--- Claude Code (.claude/agents/) ---"
  generate_agents "claude"
fi

if [ "$MODE" = "all" ] || [ "$MODE" = "--opencode" ]; then
  echo ""
  echo "--- OpenCode (.opencode/agents/) ---"
  generate_agents "opencode"
fi

echo ""
echo "✓ Генерация завершена."
