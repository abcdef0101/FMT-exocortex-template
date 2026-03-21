#!/usr/bin/env bash
# Library-Class: entrypoint-helper

if [[ -n "${_UPDATE_LIB_UPSTREAM_LOADED:-}" ]]; then
  return 0
fi
readonly _UPDATE_LIB_UPSTREAM_LOADED=1

function exo_print_update_banner() {
  local exocortex_dir="${1}"
  echo "=========================================="
  echo "  Exocortex Update"
  echo "=========================================="
  echo "  Source: ${exocortex_dir}"
  echo ""
}

function exo_ensure_upstream_remote() {
  echo "[1/6] Fetching upstream..."
  if ! git remote | grep -q upstream; then
    echo "  Adding upstream remote..."
    git remote add upstream https://github.com/TserenTserenov/FMT-exocortex-template.git
  fi

  git fetch upstream main 2>&1 | sed 's/^/  /'
}

function exo_collect_upstream_state() {
  UPDATE_LOCAL_SHA=$(git rev-parse HEAD)
  UPDATE_UPSTREAM_SHA=$(git rev-parse upstream/main)
  UPDATE_BASE_SHA=$(git merge-base HEAD upstream/main)
  UPDATE_COMMITS_BEHIND=$(git rev-list --count HEAD..upstream/main)
}

function exo_check_upstream_status() {
  exo_collect_upstream_state

  if [[ "${UPDATE_LOCAL_SHA}" == "${UPDATE_UPSTREAM_SHA}" ]]; then
    echo "  Already up to date."
    return 10
  fi

  echo "  ${UPDATE_COMMITS_BEHIND} new commits from upstream"
  echo ""
  echo "  Changes:"
  git log --oneline HEAD..upstream/main | sed 's/^/    /'
  echo ""
  return 0
}

function exo_merge_upstream() {
  local dry_run="${1}"

  echo "[2/6] Merging upstream..."

  if [[ "${dry_run}" == "true" ]]; then
    echo "  [DRY RUN] Would merge ${UPDATE_COMMITS_BEHIND} commits"
    echo "  Files that would change:"
    git diff --stat HEAD..upstream/main | sed 's/^/    /'
    return 0
  fi

  local stashed=false
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "  Stashing local changes..."
    git stash push -m "pre-update stash $(date +%Y-%m-%d)"
    stashed=true
  fi

  if ! git merge upstream/main --no-edit 2>&1 | sed 's/^/  /'; then
    echo ""
    echo "ERROR: Merge conflict. Resolve manually:"
    echo "  cd ${EXOCORTEX_DIR}"
    echo "  git status  # see conflicting files"
    echo "  # resolve conflicts, then: git add . && git merge --continue"
    return 1
  fi

  if [[ "${stashed}" == "true" ]]; then
    echo "  Restoring local changes..."
    git stash pop || echo "  WARN: Stash pop conflict. Run 'git stash pop' manually."
  fi
}
