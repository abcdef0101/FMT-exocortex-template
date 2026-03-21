#!/usr/bin/env bash
# Library-Class: entrypoint-helper

if [[ -n "${_STRATEGIST_LIB_RUNNER_LOADED:-}" ]]; then
  return 0
fi
readonly _STRATEGIST_LIB_RUNNER_LOADED=1

function strategist_already_ran_today() {
  local log_file="${1}"
  local scenario="${2}"
  [[ -f "${log_file}" ]] && grep -q "Completed scenario: ${scenario}" "${log_file}"
}

function strategist_run_scenario() {
  local command_file="${1}"
  local prompts_dir="${2}"
  local workspace="${3}"
  local claude_path="${4}"
  local log_file="${5}"
  local iso_date="${6}"
  local day_of_week="${7}"
  local log_callback="${8}"
  local notify_callback="${9}"

  local command_path prompt ru_date_context summary
  command_path="${prompts_dir}/${command_file}.md"

  case "${command_file}" in
    */*|*..*)
      "${log_callback}" "ERROR: Invalid command_file (traversal): ${command_file}"
      return 1
      ;;
  esac

  if [[ ! -f "${command_path}" ]]; then
    "${log_callback}" "ERROR: Command file not found: ${command_path}"
    return 1
  fi

  prompt=$(<"${command_path}")
  ru_date_context="$(strategist_build_ru_date_context "${iso_date}")"
  prompt="[Системный контекст] Сегодня: ${ru_date_context}. ISO: ${iso_date}. День недели №${day_of_week} (1=Пн..7=Вс).

${prompt}"

  "${log_callback}" "Starting scenario: ${command_file}"
  "${log_callback}" "Command file: ${command_path}"
  "${log_callback}" "Date context: ${ru_date_context}"

  (
    cd "${workspace}" || { "${log_callback}" "ERROR: Cannot cd to WORKSPACE: ${workspace}"; exit 1; }
    "${claude_path}" --dangerously-skip-permissions \
      --allowedTools "Read,Write,Edit,Glob,Grep,Bash" \
      -p "${prompt}" \
      >> "${log_file}" 2>&1
  )

  "${log_callback}" "Completed scenario: ${command_file}"

  if git -C "${workspace}" diff --quiet origin/main..HEAD 2>/dev/null; then
    "${log_callback}" "No unpushed commits"
  else
    git -C "${workspace}" pull --rebase >> "${log_file}" 2>&1 && "${log_callback}" "Pulled (rebase)" || "${log_callback}" "WARN: pull --rebase failed"
    git -C "${workspace}" push >> "${log_file}" 2>&1 && "${log_callback}" "Pushed to GitHub" || "${log_callback}" "WARN: git push failed"
  fi

  git -C "${workspace}" reset --quiet 2>/dev/null || true
  "${log_callback}" "Cleared staging area after Claude session"

  summary=$(tail -5 "${log_file}" | grep -v '^\[' | head -3) || true
  "${notify_callback}" "Стратег: ${command_file}" "${summary}"
}
