#!/usr/bin/env bash
# Library-Class: entrypoint-helper

if [[ -n "${_EXTRACTOR_LIB_RUNNER_LOADED:-}" ]]; then
  return 0
fi
readonly _EXTRACTOR_LIB_RUNNER_LOADED=1

function extractor_log() {
  local log_file="${1}"
  shift
  local message="$*"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${message}" >> "${log_file}"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${message}"
}

function extractor_prompt_with_context() {
  local command_path="${1}"
  local extra_context="${2:-}"
  local prompt
  prompt=$(<"${command_path}")

  if [[ -n "${extra_context}" ]]; then
    prompt="${prompt}

## Дополнительный контекст

${extra_context}"
  fi

  printf '%s' "${prompt}"
}

function extractor_run_process() {
  local process_name="${1}"
  local prompts_dir="${2}"
  local workspace_dir="${3}"
  local ai_cli="${4}"
  local ai_cli_prompt_flag="${5}"
  local ai_cli_extra_flags="${6}"
  local log_file="${7}"
  local extra_context="${8:-}"

  local command_path prompt
  command_path="${prompts_dir}/${process_name}.md"

  if [[ ! -f "${command_path}" ]]; then
    extractor_log "${log_file}" "ERROR: Command file not found: ${command_path}"
    return 1
  fi

  prompt="$(extractor_prompt_with_context "${command_path}" "${extra_context}")"

  extractor_log "${log_file}" "Starting process: ${process_name}"
  extractor_log "${log_file}" "Command file: ${command_path}"

  cd "${workspace_dir}"
  # shellcheck disable=SC2086
  "${ai_cli}" ${ai_cli_extra_flags} ${ai_cli_prompt_flag} "${prompt}" >> "${log_file}" 2>&1

  extractor_log "${log_file}" "Completed process: ${process_name}"
}
