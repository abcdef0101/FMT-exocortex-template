#!/usr/bin/env bash
# ai-cli-wrapper.sh — провайдер-агностик запуск AI CLI (Claude Code / OpenCode)
# Использование:
#   source scripts/ai-cli-wrapper.sh
#   ai_cli_run "prompt text" [--bare] [--allowed-tools "Read,Write,..."] [--budget 1.00]
#
# Или прямой вызов:
#   bash scripts/ai-cli-wrapper.sh run "prompt" --bare --allowed-tools "Read,Bash"
#   bash scripts/ai-cli-wrapper.sh check     # проверяет доступность AI CLI
#   bash scripts/ai-cli-wrapper.sh agent-create strategist-test "Read,Write,Edit,Bash"
set -euo pipefail

# === Detection ===
detect_ai_cli() {
  AI_CLI="${AI_CLI:-}"
  if [ -z "$AI_CLI" ]; then
    if command -v claude >/dev/null 2>&1; then
      AI_CLI="claude"
    elif command -v opencode >/dev/null 2>&1; then
      AI_CLI="opencode"
    else
      AI_CLI="claude"  # fallback — ошибка будет при запуске
    fi
  fi
  echo "$AI_CLI"
}

# === Flag mapping ===
# Maps provider-agnostic flags to provider-specific ones.
# Usage: ai_cli_flags [--bare] [--allowed-tools "A,B"] [--budget N]
# Output: string of CLI flags for the detected provider

ai_cli_flags() {
  local bare=false
  local tools=""
  local budget=""
  local provider
  provider=$(detect_ai_cli)

  while [ $# -gt 0 ]; do
    case "$1" in
      --bare) bare=true; shift ;;
      --allowed-tools) tools="$2"; shift 2 ;;
      --budget) budget="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  case "$provider" in
    claude)
      local flags="--dangerously-skip-permissions"
      $bare && flags="$flags --bare"
      [ -n "$tools" ] && flags="$flags --allowedTools $tools"
      [ -n "$budget" ] && flags="$flags --max-budget-usd $budget"
      echo "$flags"
      ;;
    opencode)
      local flags="--dangerously-skip-permissions"
      $bare && flags="$flags --pure"
      if [ -n "$tools" ]; then
        # opencode agents manage tools per-agent, not per-call.
        # Use 'build' agent (all permissions) or AI_CLI_AGENT override.
        local agent="${AI_CLI_AGENT:-build}"
        flags="$flags --agent $agent"
      fi
      [ -n "$budget" ] && flags="$flags --variant minimal"
      echo "$flags"
      ;;
    *)
      echo "--dangerously-skip-permissions"
      ;;
  esac
}

# === Run AI CLI ===
# Usage: ai_cli_run "prompt" [--bare] [--allowed-tools "A,B"] [--budget N] [--timeout 300]
# All additional arguments after prompt are forwarded to ai_cli_flags

ai_cli_run() {
  local prompt="$1"; shift
  local provider timeout_val flags
  provider=$(detect_ai_cli)
  timeout_val="${AI_CLI_TIMEOUT:-300}"
  flags=$(ai_cli_flags "$@")

  case "$provider" in
    claude)
      timeout "$timeout_val" claude $flags -p "$prompt"
      local claude_rc=$?
      if [ $claude_rc -ne 0 ]; then
        if command -v opencode >/dev/null 2>&1; then
          echo "WARN: claude unavailable (rc=$claude_rc), falling back to opencode" >&2
          timeout "$timeout_val" opencode run "$prompt" \
            -m "${AI_CLI_MODEL:-anthropic/claude-sonnet-4-20250514}" --dangerously-skip-permissions --pure
          return $?
        fi
      fi
      return $claude_rc
      ;;
    opencode)
      # Setup custom provider config if needed (baseURL or full config)
      if [ -n "${AI_CLI_BASE_URL:-}" ]; then
        _opencode_setup_config
      elif [ -n "${AI_CLI_CONFIG:-}" ]; then
        mkdir -p ~/.config/opencode 2>/dev/null || true
        echo "$AI_CLI_CONFIG" > ~/.config/opencode/opencode.json
      fi
      # Validate model is in provider/model format
      local model="${AI_CLI_MODEL:-anthropic/claude-sonnet-4-20250514}"
      if [[ "$model" != */* ]]; then
        # shellcheck disable=SC2086 — $model safe in [[ ]] (bash builtin, no word splitting)
        echo "WARN: AI_CLI_MODEL missing provider prefix. Use 'provider/model' format (e.g. 'anthropic/claude-sonnet-4'). Got: '$model'" >&2
      fi
      # opencode uses 'run' subcommand + -m provider/model
      timeout "$timeout_val" opencode run "$prompt" \
        -m "$model" $flags
      ;;
    *)
      echo "ERROR: unknown AI CLI: $provider" >&2
      return 1
      ;;
  esac
}

# === Custom provider setup (opencode) ===
# Generates opencode.json from AI_CLI_BASE_URL + AI_CLI_MODEL env vars.
# Used when AI_CLI_BASE_URL is set (custom API endpoint).

_opencode_setup_config() {
  local base_url="${AI_CLI_BASE_URL}"
  local model_id="${AI_CLI_MODEL##*/}"  # extract "my-model" from "custom/my-model"
  local model_name="${model_id:-custom-model}"

  mkdir -p ~/.config/opencode 2>/dev/null || true

  [ -f ~/.config/opencode/opencode.json ] && cp ~/.config/opencode/opencode.json ~/.config/opencode/opencode.json.bak

  cat > ~/.config/opencode/opencode.json <<OPECFG
{
  "\$schema": "https://opencode.ai/config.json",
  "provider": {
    "custom": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Custom API (${base_url})",
      "options": {
        "baseURL": "${base_url}"
      },
      "models": {
        "${model_id}": {
          "name": "${model_name}"
        }
      }
    }
  }
}
OPECFG
}

# === Model tier resolution ===
# Reads model-tiers.yaml to map capability tier → model ID per provider.
# Usage: resolve_model [fast|thinking|pro]
# Fallback chain: $WORKSPACE_DIR/model-tiers.yaml → seed/model-tiers.yaml

resolve_model() {
  local tier="${1:-thinking}"
  local provider
  provider=$(detect_ai_cli)

  local provider_key
  case "$provider" in
    claude) provider_key="anthropic" ;;
    opencode)
      if [ -n "${AI_CLI_MODEL:-}" ] && [[ "$AI_CLI_MODEL" == */* ]]; then
        provider_key="${AI_CLI_MODEL%%/*}"
      else
        provider_key="anthropic"
      fi
      ;;
    *) provider_key="anthropic" ;;
  esac

  local tiers_file=""
  for cand in \
    "${WORKSPACE_DIR:-}/model-tiers.yaml" \
    "seed/model-tiers.yaml" \
    "${FMT_DIR:-}/seed/model-tiers.yaml"; do
    [ -n "$cand" ] && [ -f "$cand" ] && { tiers_file="$cand"; break; }
  done

  if [ -z "$tiers_file" ]; then
    echo "ERROR: model-tiers.yaml not found for provider=$provider_key tier=$tier" >&2
    return 1
  fi

  local model_id
  model_id=$(awk -v prov="$provider_key" -v t="$tier" '
    $0 ~ "^" prov ":" { in_block=1; next }
    in_block && /^[a-z]/ { exit }
    in_block && $1 ~ "^" t ":" { gsub(/[" ]/,""); sub(/^[^:]*:/,""); print; exit }
  ' "$tiers_file")

  if [ -z "$model_id" ]; then
    echo "ERROR: no model found for provider=$provider_key tier=$tier in $tiers_file" >&2
    return 1
  fi

  echo "$model_id"
}

# === Agent management ===
# opencode: create agent with allowed tools (idempotent — skips if exists)
# claude: uses --allowedTools flag directly, no agent needed

_opencode_ensure_agent() {
  local agent_name="$1" tools="$2"
  # Check if agent already exists
  if opencode agent list 2>/dev/null | grep -q "\"name\": \"$agent_name\"" 2>/dev/null; then
    return 0  # already created
  fi
  opencode agent create --name "$agent_name" --tools "$tools" --mode primary 2>/dev/null || true
}

ai_cli_agent_create() {
  local agent_name="${1:-strategist-test}"
  local tools="${2:-Read,Write,Edit,Glob,Grep,Bash}"
  local provider
  provider=$(detect_ai_cli)

  case "$provider" in
    opencode)
      local oc_tools
      oc_tools=$(echo "$tools" | tr '[:upper:]' '[:lower:]' | sed 's/write/edit/g' | tr ',' ' ')
      _opencode_ensure_agent "$agent_name" "$oc_tools"
      echo "  Agent '$agent_name' ready (tools: $oc_tools)"
      ;;
    claude)
      # claude uses --allowedTools flag directly, no agent needed
      return 0
      ;;
  esac
}

# === Main (when invoked directly) ===
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  COMMAND="${1:-help}"
  case "$COMMAND" in
    run)
      shift
      PROMPT="$1"; shift
      ai_cli_run "$PROMPT" "$@"
      ;;
    check)
      PROVIDER=$(detect_ai_cli)
      if command -v "$PROVIDER" >/dev/null 2>&1; then
        echo "AI CLI: $PROVIDER ($(command -v "$PROVIDER"))"
        exit 0
      else
        echo "No AI CLI found (checked: claude, opencode)" >&2
        exit 1
      fi
      ;;
    agent-create)
      shift
      ai_cli_agent_create "$@"
      ;;
    resolve)
      shift
      resolve_model "$@"
      ;;
    flags)
      shift
      ai_cli_flags "$@"
      ;;
    *)
      echo "Usage: ai-cli-wrapper.sh {run|check|agent-create|resolve|flags} [args...]" >&2
      echo "" >&2
      echo "Commands:" >&2
      echo "  run PROMPT [--bare] [--allowed-tools A,B] [--budget N]  Run AI CLI" >&2
      echo "  check                   Check AI CLI availability" >&2
      echo "  agent-create NAME TOOLS              Create agent (opencode)" >&2
      echo "  resolve TIER            Resolve capability tier to model ID" >&2
      echo "  flags [--bare] [--allowed-tools A,B] Print CLI flags" >&2
      echo "" >&2
      echo "Provider: $(detect_ai_cli)" >&2
      exit 1
      ;;
  esac
fi
