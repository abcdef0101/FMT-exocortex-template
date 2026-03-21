#!/usr/bin/env bash
# Library-Class: entrypoint-helper

if [[ -n "${_SETUP_LIB_VERIFY_LOADED:-}" ]]; then
  return 0
fi
readonly _SETUP_LIB_VERIFY_LOADED=1

function exo_print_setup_result() {
  local dry_run="${1}"
  local core_only="${2}"
  local template_dir="${3}"
  local workspace_dir="${4}"
  local claude_memory_dir="${5}"
  local strategy_dir="${6}"

  echo ""
  if [[ "${dry_run}" == "true" ]]; then
    echo "=========================================="
    echo "  [DRY RUN] No changes made."
    echo "=========================================="
    echo ""
    echo "Run 'bash setup.sh' (without --dry-run) to apply."
    return 0
  fi

  echo "=========================================="
  if [[ "${core_only}" == "true" ]]; then
    echo "  Setup Complete! (core)"
  else
    echo "  Setup Complete!"
  fi
  echo "=========================================="
  echo ""
  echo "Verify installation:"
  echo "  ✓ CLAUDE.md:   ${workspace_dir}/CLAUDE.md"
  echo "  ✓ Memory:      ${claude_memory_dir}/ ($(find "${claude_memory_dir}" -maxdepth 1 -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ') files)"
  echo "  ✓ Symlink:     ${workspace_dir}/memory → ${claude_memory_dir}"
  echo "  ✓ DS-strategy: ${strategy_dir}/"
  echo "  ✓ Template:    ${template_dir}/"
  echo ""

  if [[ "${core_only}" == "true" ]]; then
    echo "Next steps:"
    echo "  1. cd ${workspace_dir}"
    echo "  2. Запустите ваш AI CLI (Claude Code, Codex, Aider, Continue.dev и др.)"
    echo "  3. Скажите: «Проведём первую стратегическую сессию»"
    echo ""
    echo "Переход на полную установку (GitHub + автоматизация):"
    echo "  bash ${template_dir}/setup.sh"
    echo ""
    return 0
  fi

  echo "Next steps:"
  echo "  1. cd ${workspace_dir}"
  echo "  2. claude"
  echo "  3. Ask Claude: «Проведём первую стратегическую сессию»"
  echo ""
  echo "Strategist will run automatically:"
  echo "  - Morning (${TIMEZONE_DESC}): strategy (Mon) / day-plan (Tue-Sun)"
  echo "  - Sunday night: week review"
  echo ""
  echo "Update from upstream:"
  echo "  cd ${template_dir} && bash update.sh"
  echo ""
}
