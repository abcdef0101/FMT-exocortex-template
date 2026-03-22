#!/usr/bin/env bash
# Library-Class: entrypoint-helper

if [[ -n "${_CODE_SCAN_LIB_LOADED:-}" ]]; then
  return 0
fi
readonly _CODE_SCAN_LIB_LOADED=1

function code_scan_log() {
  local log_file="${1}"
  shift
  local message="$*"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [code-scan] ${message}" | tee -a "${log_file}"
}

function code_scan_discover_repos() {
  local workspace_dir="${1}"
  local dir name skip

  for dir in "${workspace_dir}"/DS-*/; do
    [[ -d "${dir}/.git" ]] || continue
    name=$(basename "$dir")
    skip=false
    [[ "$name" == "DS-strategy" ]] && skip=true
    [[ "$skip" == true ]] && continue
    printf '%s\n' "${dir}"
  done
}

function code_scan_run() {
  local workspace_dir="${1}"
  local log_file="${2}"
  local dry_run="${3}"

  local total_repos=0 total_commits=0 repo_dir repo_name commits count
  while IFS= read -r repo_dir; do
    repo_dir="${repo_dir%/}"
    repo_name=$(basename "$repo_dir")
    commits=$(git -C "$repo_dir" log --since="24 hours ago" --oneline --no-merges 2>/dev/null || true)

    if [[ -z "$commits" ]]; then
      code_scan_log "$log_file" "SKIP: $repo_name — нет коммитов за 24ч"
      continue
    fi

    count=$(echo "$commits" | wc -l | tr -d ' ')
    code_scan_log "$log_file" "FOUND: $repo_name — $count коммитов"
    total_repos=$((total_repos + 1))
    total_commits=$((total_commits + count))
  done < <(code_scan_discover_repos "$workspace_dir")

  code_scan_log "$log_file" "Итого: $total_repos репо, $total_commits коммитов"
}
