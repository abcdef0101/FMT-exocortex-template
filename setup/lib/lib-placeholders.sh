#!/usr/bin/env bash
# Library-Class: entrypoint-helper

if [[ -n "${_SETUP_LIB_PLACEHOLDERS_LOADED:-}" ]]; then
  return 0
fi
readonly _SETUP_LIB_PLACEHOLDERS_LOADED=1

function exo_configure_placeholders() {
  local dry_run="${1}"
  local template_dir="${2}"

  echo "[1/6] Configuring placeholders..."

  if [[ "${dry_run}" == "true" ]]; then
    local placeholder_files
    placeholder_files=$(find "${template_dir}" -type f \( -name "*.md" -o -name "*.json" -o -name "*.plist" -o -name "*.yaml" -o -name "*.yml" -o -name "*.service" -o -name "*.timer" \) | wc -l | tr -d ' ')
    echo "  [DRY RUN] Would substitute placeholders in ${placeholder_files} files"
    echo "    {{GITHUB_USER}} → ${GITHUB_USER}"
    echo "    {{WORKSPACE_DIR}} → ${WORKSPACE_DIR}"
    echo "    {{EXOCORTEX_REPO}} → ${EXOCORTEX_REPO}"
    echo "    {{CLAUDE_PATH}} → ${CLAUDE_PATH}"
    echo "    {{CLAUDE_PROJECT_SLUG}} → ${CLAUDE_PROJECT_SLUG}"
    echo "    {{TIMEZONE_HOUR}} → ${TIMEZONE_HOUR}"
    echo "    {{TIMEZONE_DESC}} → ${TIMEZONE_DESC}"
    echo "    {{HOME_DIR}} → ${HOME_DIR}"
    return 0
  fi

  while IFS= read -r -d '' file; do
    iwe_sed_inplace \
      -e "s|{{GITHUB_USER}}|${GITHUB_USER}|g" \
      -e "s|{{WORKSPACE_DIR}}|${WORKSPACE_DIR}|g" \
      -e "s|{{EXOCORTEX_REPO}}|${EXOCORTEX_REPO}|g" \
      -e "s|{{CLAUDE_PATH}}|${CLAUDE_PATH}|g" \
      -e "s|{{CLAUDE_PROJECT_SLUG}}|${CLAUDE_PROJECT_SLUG}|g" \
      -e "s|{{TIMEZONE_HOUR}}|${TIMEZONE_HOUR}|g" \
      -e "s|{{TIMEZONE_DESC}}|${TIMEZONE_DESC}|g" \
      -e "s|{{HOME_DIR}}|${HOME_DIR}|g" \
      "${file}"
  done < <(find "${template_dir}" -type f \( -name "*.md" -o -name "*.json" -o -name "*.plist" -o -name "*.yaml" -o -name "*.yml" -o -name "*.service" -o -name "*.timer" \) -print0)

  echo "  Placeholders substituted."

  if [[ -d "${template_dir}/.githooks" ]]; then
    git -C "${template_dir}" config core.hooksPath .githooks 2>/dev/null &&
      echo "  Pre-commit hook enabled (.githooks/)" || true
  fi
}

function exo_maybe_rename_repo() {
  local dry_run="${1}"
  local core_only="${2}"
  local template_dir="${3}"

  local current_dir_name target_dir
  current_dir_name="$(basename "${template_dir}")"

  if [[ "${EXOCORTEX_REPO}" == "${current_dir_name}" ]]; then
    echo "  Repo name unchanged (${current_dir_name})." >&2
    printf '%s\n' "${template_dir}"
    return 0
  fi

  echo "" >&2
  echo "[1b] Renaming repo: ${current_dir_name} → ${EXOCORTEX_REPO}..." >&2
  target_dir="$(dirname "${template_dir}")/${EXOCORTEX_REPO}"

  if [[ -d "${target_dir}" ]]; then
    echo "  WARN: ${target_dir} already exists. Skipping rename." >&2
    printf '%s\n' "${template_dir}"
    return 0
  fi

  if [[ "${dry_run}" == "true" ]]; then
    echo "  [DRY RUN] Would rename: ${template_dir} → ${target_dir}" >&2
    if [[ "${core_only}" != "true" ]] && command -v gh >/dev/null 2>&1; then
      echo "  [DRY RUN] Would rename GitHub repo to ${EXOCORTEX_REPO}" >&2
    fi
    printf '%s\n' "${template_dir}"
    return 0
  fi

  while IFS= read -r -d '' file; do
    iwe_sed_inplace "s|${current_dir_name}|${EXOCORTEX_REPO}|g" "${file}"
  done < <(find "${template_dir}" -type f \( -name "*.md" -o -name "*.json" -o -name "*.plist" -o -name "*.yaml" -o -name "*.yml" -o -name "*.service" -o -name "*.timer" \) -print0)

  if [[ "${core_only}" != "true" ]] && command -v gh >/dev/null 2>&1; then
    gh repo rename "${EXOCORTEX_REPO}" --yes 2>/dev/null &&
      echo "  ✓ GitHub repo renamed to ${EXOCORTEX_REPO}" >&2 ||
      echo "  ○ GitHub rename skipped (rename manually: gh repo rename ${EXOCORTEX_REPO})" >&2
  fi

  mv "${template_dir}" "${target_dir}"
  echo "  ✓ Local directory renamed to ${EXOCORTEX_REPO}" >&2
  printf '%s\n' "${target_dir}"
}
