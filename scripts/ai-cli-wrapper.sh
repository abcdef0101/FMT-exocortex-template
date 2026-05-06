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
      [ -n "$tools" ] && flags="$flags --allowedTools \"$tools\""
      [ -n "$budget" ] && flags="$flags --max-budget-usd $budget"
      echo "$flags"
      ;;
    opencode)
      local flags="--dangerously-skip-permissions"
      $bare && flags="$flags --pure"
      # opencode doesn't have --allowedTools CLI flag — uses agents instead.
      # The --allowed-tools param is stored for agent-based execution.
      if [ -n "$tools" ]; then
        # Export for ai_cli_run to use when creating/running agent
        export AI_CLI_TOOLS="$tools"
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

# === Agent management (opencode-specific) ===
# Creates an agent with allowed tools for opencode.
# No-op for claude.

ai_cli_agent_create() {
  local agent_name="${1:-strategist-test}"
  local tools="${2:-Read,Write,Edit,Glob,Grep,Bash}"
  local provider
  provider=$(detect_ai_cli)

  case "$provider" in
    opencode)
      # Check if agent already exists
      if opencode agent list 2>/dev/null | grep -q "$agent_name"; then
        echo "  Agent '$agent_name' already exists"
        return 0
      fi
      opencode agent create "$agent_name" \
        --tools "$tools" \
        --description "Headless agent for automated CI tasks" 2>/dev/null \
        && echo "  Agent '$agent_name' created" \
        || echo "  WARN: agent create failed (may need interactive setup)"
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
    flags)
      shift
      ai_cli_flags "$@"
      ;;
    *)
      echo "Usage: ai-cli-wrapper.sh {run|check|agent-create|flags} [args...]" >&2
      echo "" >&2
      echo "Commands:" >&2
      echo "  run PROMPT [--bare] [--allowed-tools A,B] [--budget N]  Run AI CLI" >&2
      echo "  check                   Check AI CLI availability" >&2
      echo "  agent-create NAME TOOLS              Create agent (opencode)" >&2
      echo "  flags [--bare] [--allowed-tools A,B] Print CLI flags" >&2
      echo "" >&2
      echo "Provider: $(detect_ai_cli)" >&2
      exit 1
      ;;
  esac
fi
