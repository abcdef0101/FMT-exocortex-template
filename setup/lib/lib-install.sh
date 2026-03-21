#!/usr/bin/env bash
# Library-Class: entrypoint-helper

if [[ -n "${_SETUP_LIB_INSTALL_LOADED:-}" ]]; then
  return 0
fi
readonly _SETUP_LIB_INSTALL_LOADED=1

function exo_install_claude_md() {
  local dry_run="${1}"
  local template_dir="${2}"
  local workspace_dir="${3}"

  echo "[2/6] Installing CLAUDE.md..."
  if [[ "${dry_run}" == "true" ]]; then
    echo "  [DRY RUN] Would copy: ${template_dir}/CLAUDE.md → ${workspace_dir}/CLAUDE.md"
    return 0
  fi

  cp "${template_dir}/CLAUDE.md" "${workspace_dir}/CLAUDE.md"
  echo "  Copied to ${workspace_dir}/CLAUDE.md"
}

function exo_install_memory() {
  local dry_run="${1}"
  local template_dir="${2}"
  local workspace_dir="${3}"
  local claude_memory_dir="${HOME}/.claude/projects/${CLAUDE_PROJECT_SLUG}/memory"

  echo "[3/6] Installing memory..."
  if [[ "${dry_run}" == "true" ]]; then
    local mem_count
    mem_count=$(find "${template_dir}/memory" -maxdepth 1 -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
    echo "  [DRY RUN] Would copy ${mem_count} memory files → ${claude_memory_dir}/" >&2
    if [[ ! -e "${workspace_dir}/memory" ]]; then
      echo "  [DRY RUN] Would create symlink: ${workspace_dir}/memory → ${claude_memory_dir}" >&2
    else
      echo "  WARN: ${workspace_dir}/memory already exists, symlink would be skipped." >&2
    fi
    printf '%s\n' "${claude_memory_dir}"
    return 0
  fi

  mkdir -p "${claude_memory_dir}"
  cp "${template_dir}/memory/"*.md "${claude_memory_dir}/"
  echo "  Copied to ${claude_memory_dir}" >&2

  if [[ ! -e "${workspace_dir}/memory" ]]; then
    ln -s "${claude_memory_dir}" "${workspace_dir}/memory"
    echo "  Symlink: ${workspace_dir}/memory → ${claude_memory_dir}" >&2
  else
    echo "  WARN: ${workspace_dir}/memory already exists, symlink skipped." >&2
  fi

  printf '%s\n' "${claude_memory_dir}"
}

function exo_install_claude_settings() {
  local dry_run="${1}"
  local core_only="${2}"
  local template_dir="${3}"
  local workspace_dir="${4}"

  if [[ "${core_only}" == "true" ]]; then
    echo "[4/6] Claude settings... пропущено (--core)"
    return 0
  fi

  echo "[4/6] Installing Claude settings..."
  if [[ "${dry_run}" == "true" ]]; then
    if [[ -f "${template_dir}/.claude/settings.local.json" ]]; then
      echo "  [DRY RUN] Would copy: settings.local.json → ${workspace_dir}/.claude/settings.local.json"
    else
      echo "  WARN: settings.local.json not found in template."
    fi
    echo "  [DRY RUN] Would register MCP servers: knowledge-mcp, ddt"
    return 0
  fi

  mkdir -p "${workspace_dir}/.claude"
  if [[ -f "${template_dir}/.claude/settings.local.json" ]]; then
    cp "${template_dir}/.claude/settings.local.json" "${workspace_dir}/.claude/settings.local.json"
    echo "  Copied to ${workspace_dir}/.claude/settings.local.json"
  else
    echo "  WARN: settings.local.json not found in template, skipping."
  fi

  echo "  Adding MCP servers..."
  cd "${workspace_dir}" || {
    echo "ERROR: Cannot cd to ${workspace_dir}" >&2
    return 1
  }
  claude mcp add --transport http --scope project knowledge-mcp "https://knowledge-mcp.aisystant.workers.dev/mcp" 2>/dev/null &&
    echo "  ✓ knowledge-mcp added" ||
    echo "  ○ knowledge-mcp: add manually: claude mcp add --transport http knowledge-mcp https://knowledge-mcp.aisystant.workers.dev/mcp"
  claude mcp add --transport http --scope project ddt "https://digital-twin-mcp.aisystant.workers.dev/mcp" 2>/dev/null &&
    echo "  ✓ ddt added" ||
    echo "  ○ ddt: add manually: claude mcp add --transport http ddt https://digital-twin-mcp.aisystant.workers.dev/mcp"
}

function exo_install_roles() {
  local dry_run="${1}"
  local core_only="${2}"
  local template_dir="${3}"

  if [[ "${core_only}" == "true" ]]; then
    echo "[5/6] Автоматизация... пропущена (--core)"
    echo "  Установить позже: см. ${template_dir}/roles/ROLE-CONTRACT.md"
    return 0
  fi

  echo "[5/6] Installing roles..."
  local -a manual_roles=()
  local role_dir role_yaml role_name runner display

  for role_dir in "${template_dir}"/roles/*/; do
    [[ -d "${role_dir}" ]] || continue
    role_yaml="${role_dir}/role.yaml"
    [[ -f "${role_yaml}" ]] || continue
    role_name="$(basename "${role_dir}")"

    if grep -q 'auto:.*true' "${role_yaml}" 2>/dev/null; then
      if [[ -f "${role_dir}/install.sh" ]]; then
        if [[ "${dry_run}" == "true" ]]; then
          echo "  [DRY RUN] Would install role: ${role_name} (auto)"
        else
          chmod +x "${role_dir}/install.sh"
          runner=$(grep '^runner:' "${role_yaml}" | sed 's/runner: *//' | tr -d '"' | tr -d "'") || true
          [[ -n "${runner}" ]] && chmod +x "${role_dir}/${runner}" 2>/dev/null || true
          bash "${role_dir}/install.sh"
          echo "  ✓ ${role_name} installed"
        fi
      else
        echo "  WARN: ${role_name}/install.sh not found, skipping."
      fi
    else
      display=$(grep 'display_name:' "${role_yaml}" 2>/dev/null | sed 's/display_name: *//' | tr -d '"') || true
      manual_roles+=("  - ${display:-${role_name}}: bash ${role_dir}/install.sh")
    fi
  done

  if [[ "${#manual_roles[@]}" -gt 0 ]]; then
    echo ""
    echo "  Additional roles (install later when ready):"
    printf '%s\n' "${manual_roles[@]}"
    echo "  See: ${template_dir}/roles/ROLE-CONTRACT.md"
  fi
}

function exo_setup_strategy_repo() {
  local dry_run="${1}"
  local core_only="${2}"
  local template_dir="${3}"
  local workspace_dir="${4}"

  local my_strategy_dir="${workspace_dir}/DS-strategy"
  local strategy_template="${template_dir}/seed/strategy"

  echo "[6/6] Setting up DS-strategy..."

  if [[ -d "${my_strategy_dir}/.git" ]]; then
    echo "  DS-strategy already exists as git repo." >&2
    printf '%s\n' "${my_strategy_dir}"
    return 0
  fi

  if [[ "${dry_run}" == "true" ]]; then
    if [[ -d "${strategy_template}" ]]; then
      echo "  [DRY RUN] Would create DS-strategy from seed/strategy → ${my_strategy_dir}" >&2
      echo "  [DRY RUN] Would init git repo + initial commit" >&2
      if [[ "${core_only}" != "true" ]]; then
        echo "  [DRY RUN] Would create GitHub repo: ${GITHUB_USER}/DS-strategy (private)" >&2
      fi
    else
      echo "  [DRY RUN] Would create minimal DS-strategy (seed/strategy not found)" >&2
    fi
    printf '%s\n' "${my_strategy_dir}"
    return 0
  fi

  if [[ -d "${strategy_template}" ]]; then
    cp -r "${strategy_template}" "${my_strategy_dir}"
    cd "${my_strategy_dir}" || {
      echo "ERROR: Cannot cd to ${my_strategy_dir}" >&2
      return 1
    }
    git init
    git add -A
    git commit -m "Initial exocortex: DS-strategy governance hub"

    if [[ "${core_only}" != "true" ]]; then
      gh repo create "${GITHUB_USER}/DS-strategy" --private --source=. --push 2>/dev/null ||
        echo "  GitHub repo DS-strategy already exists or creation skipped." >&2
    else
      echo "  Локальный репозиторий создан. Для публикации на GitHub:" >&2
      echo "    cd ${my_strategy_dir} && gh repo create ${GITHUB_USER}/DS-strategy --private --source=. --push" >&2
    fi
    printf '%s\n' "${my_strategy_dir}"
    return 0
  fi

  echo "  ERROR: seed/strategy/ not found. DS-strategy will be incomplete." >&2
  echo "  Fix: re-clone the template and run setup.sh again." >&2
  echo "  Creating minimal structure as fallback..." >&2
  mkdir -p "${my_strategy_dir}"/{current,inbox,archive/wp-contexts,docs,exocortex}
  cd "${my_strategy_dir}" || {
    echo "ERROR: Cannot cd to ${my_strategy_dir}" >&2
    return 1
  }
  git init
  git add -A
  git commit -m "Initial exocortex: DS-strategy governance hub (minimal)" 2>/dev/null || true

  if [[ "${core_only}" != "true" ]]; then
    gh repo create "${GITHUB_USER}/DS-strategy" --private --source=. --push 2>/dev/null ||
      echo "  GitHub repo DS-strategy already exists or creation skipped." >&2
  fi

  printf '%s\n' "${my_strategy_dir}"
}
