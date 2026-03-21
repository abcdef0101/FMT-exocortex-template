#!/usr/bin/env bash
# Library-Class: entrypoint-helper

if [[ -n "${_UPDATE_LIB_REFRESH_LOADED:-}" ]]; then
  return 0
fi
readonly _UPDATE_LIB_REFRESH_LOADED=1

function exo_refresh_placeholders() {
  local dry_run="${1}"
  local exocortex_dir="${2}"
  local workspace_dir="${3}"

  echo "[3/6] Re-substituting placeholders..."

  local placeholder_count
  placeholder_count=$(grep -rF '{{WORKSPACE_DIR}}' "${exocortex_dir}" --include="*.md" --include="*.sh" --include="*.json" --include="*.yaml" --include="*.yml" --include="*.plist" -l 2>/dev/null | wc -l | tr -d ' ')

  if [[ "${placeholder_count}" -gt 0 ]]; then
    echo "  Found ${placeholder_count} files with unsubstituted {{WORKSPACE_DIR}}"
    if [[ "${dry_run}" == "true" ]]; then
      echo "  [DRY RUN] Would re-substitute {{WORKSPACE_DIR}} → ${workspace_dir} in ${placeholder_count} files"
    else
      while IFS= read -r -d '' file; do
        iwe_sed_inplace "s|{{WORKSPACE_DIR}}|${workspace_dir}|g" "${file}"
      done < <(
        grep -rFlZ '{{WORKSPACE_DIR}}' "${exocortex_dir}" \
          --include="*.md" --include="*.sh" --include="*.json" \
          --include="*.yaml" --include="*.yml" --include="*.plist" \
          --include="*.service" --include="*.timer" 2>/dev/null
      )
      echo "  Re-substituted {{WORKSPACE_DIR}} → ${workspace_dir}"

      if ! git -C "${exocortex_dir}" diff --quiet; then
        git -C "${exocortex_dir}" add -A
        git -C "${exocortex_dir}" commit -m "chore: re-substitute placeholders after upstream merge" --no-verify 2>&1 | sed 's/^/  /'
      fi
    fi
  else
    echo "  No unsubstituted placeholders found"
  fi

  local remaining
  remaining=$(grep -rF '{{' "${exocortex_dir}" --include="*.md" --include="*.sh" --include="*.json" --include="*.yaml" -l 2>/dev/null | xargs grep -lF '}}' 2>/dev/null | wc -l | tr -d ' ')
  if [[ "${remaining}" -gt 0 ]]; then
    echo "  WARN: ${remaining} files still have unsubstituted placeholders."
    echo "  Run 'bash setup.sh' to re-substitute all placeholders."
  fi
}

function exo_show_release_notes() {
  local exocortex_dir="${1}"

  echo "[4/6] Release notes..."
  if [[ -f "${exocortex_dir}/CHANGELOG.md" ]]; then
    echo ""
    echo "  ┌──────────────────────────────────────┐"
    echo "  │         What's New                   │"
    echo "  └──────────────────────────────────────┘"
    awk '/^## \[/{if(found) exit; found=1; next} found{print}' "${exocortex_dir}/CHANGELOG.md" | head -30 | sed 's/^/  /'
    echo ""
  else
    echo "  No CHANGELOG.md found"
  fi
}

function exo_reinstall_platform_space() {
  local dry_run="${1}"
  local exocortex_dir="${2}"
  local workspace_dir="${3}"

  echo "[5/6] Reinstalling platform-space..."

  if [[ -f "${exocortex_dir}/CLAUDE.md" ]]; then
    if [[ "${dry_run}" == "true" ]]; then
      echo "  [DRY RUN] Would update: ${workspace_dir}/CLAUDE.md"
    else
      cp "${exocortex_dir}/CLAUDE.md" "${workspace_dir}/CLAUDE.md"
      echo "  Updated: ${workspace_dir}/CLAUDE.md"
    fi
  fi

  local ontology_src ontology_dst user_sections
  ontology_src="${exocortex_dir}/ONTOLOGY.md"
  ontology_dst="${workspace_dir}/ONTOLOGY.md"
  if [[ -f "${ontology_src}" ]]; then
    if [[ -f "${ontology_dst}" ]]; then
      user_sections=$(sed -n '/^<!-- USER-SPACE/,$p' "${ontology_dst}")
      if [[ -n "${user_sections}" ]]; then
        if [[ "${dry_run}" == "true" ]]; then
          echo "  [DRY RUN] Would merge ONTOLOGY.md (platform-space from upstream, user-space preserved)"
        else
          sed '/^<!-- USER-SPACE/,$d' "${ontology_src}" > "${ontology_dst}.tmp"
          echo "${user_sections}" >> "${ontology_dst}.tmp"
          mv "${ontology_dst}.tmp" "${ontology_dst}"
          echo "  Updated: ONTOLOGY.md (platform-space merged, user-space preserved)"
        fi
      else
        if [[ "${dry_run}" == "true" ]]; then
          echo "  [DRY RUN] Would copy ONTOLOGY.md (full copy, no user-space marker found)"
        else
          cp "${ontology_src}" "${ontology_dst}"
          echo "  Updated: ONTOLOGY.md (full copy, no user-space found)"
        fi
      fi
    else
      if [[ "${dry_run}" == "true" ]]; then
        echo "  [DRY RUN] Would install: ONTOLOGY.md (new file)"
      else
        cp "${ontology_src}" "${ontology_dst}"
        echo "  Installed: ONTOLOGY.md"
      fi
    fi
  fi

  local claude_memory_dir
  claude_memory_dir="${HOME}/.claude/projects/-$(echo "${workspace_dir}" | tr '/' '-')/memory"
  if [[ -d "${exocortex_dir}/memory" ]] && [[ -d "${claude_memory_dir}" ]]; then
    local file_name file_path
    for file_path in "${exocortex_dir}/memory/"*.md; do
      file_name=$(basename "${file_path}")
      if [[ "${file_name}" != "MEMORY.md" ]]; then
        if [[ "${dry_run}" == "true" ]]; then
          echo "  [DRY RUN] Would update: memory/${file_name}"
        else
          cp "${file_path}" "${claude_memory_dir}/${file_name}"
          echo "  Updated: memory/${file_name}"
        fi
      fi
    done
    echo "  Skipped: memory/MEMORY.md (user data preserved)"
  fi

  local settings_src settings_dst
  settings_src="${exocortex_dir}/.claude/settings.local.json"
  settings_dst="${workspace_dir}/.claude/settings.local.json"
  if [[ -f "${settings_src}" ]]; then
    if [[ -f "${settings_dst}" ]]; then
      if [[ "${dry_run}" == "true" ]]; then
        echo "  [DRY RUN] Would merge .claude/settings.local.json (mcpServers from upstream, permissions preserved)"
      else
        if command -v python3 >/dev/null 2>&1; then
          python3 -c "
import json
with open('${settings_src}') as f: src = json.load(f)
with open('${settings_dst}') as f: dst = json.load(f)
dst['mcpServers'] = src.get('mcpServers', {})
src_perms = set(src.get('permissions', {}).get('allow', []))
dst_perms = set(dst.get('permissions', {}).get('allow', []))
dst.setdefault('permissions', {})['allow'] = sorted(dst_perms | src_perms)
with open('${settings_dst}', 'w') as f: json.dump(dst, f, indent=2, ensure_ascii=False)
print('  Updated: .claude/settings.local.json (merged)')
" 2>&1
        else
          cp "${settings_src}" "${settings_dst}"
          echo "  Updated: .claude/settings.local.json (replaced, python3 not found for merge)"
        fi
      fi
    else
      if [[ "${dry_run}" == "true" ]]; then
        echo "  [DRY RUN] Would install: .claude/settings.local.json (new file)"
      else
        mkdir -p "$(dirname "${settings_dst}")"
        cp "${settings_src}" "${settings_dst}"
        echo "  Installed: .claude/settings.local.json"
      fi
    fi
  fi
}

function exo_reinstall_changed_roles() {
  local dry_run="${1}"
  local exocortex_dir="${2}"

  echo "[6/6] Reinstalling roles..."
  local changed_files role_dir role_name install_script
  changed_files=$(git diff --name-only "${UPDATE_LOCAL_SHA}".."${UPDATE_UPSTREAM_SHA}" 2>/dev/null || echo "")

  for role_dir in "${exocortex_dir}"/roles/*/; do
    [[ -d "${role_dir}" ]] || continue
    role_name=$(basename "${role_dir}")
    install_script="${exocortex_dir}/roles/${role_name}/install.sh"
    [[ -f "${install_script}" ]] || continue

    if echo "${changed_files}" | grep -q "^roles/${role_name}/"; then
      if [[ "${dry_run}" == "true" ]]; then
        echo "  [DRY RUN] Would reinstall: ${role_name}"
      else
        echo "  Reinstalling ${role_name}..."
        chmod +x "${install_script}"
        bash "${install_script}" 2>&1 | sed 's/^/    /'
      fi
    else
      echo "  ${role_name}: no changes"
    fi
  done
}

function exo_finish_update() {
  local dry_run="${1}"

  if [[ "${dry_run}" == "true" ]]; then
    echo ""
    echo "[DRY RUN] No changes made. Run 'update.sh' to apply."
    return 0
  fi

  echo "Pushing merge commit..."
  git push 2>&1 | sed 's/^/  /'
  echo ""
  echo "=========================================="
  echo "  Update Complete!"
  echo "=========================================="
  echo "  Merged ${UPDATE_COMMITS_BEHIND} commits from upstream"
  echo "  Platform-space reinstalled"
  echo "  Roles checked for reinstallation"
  echo ""
}
