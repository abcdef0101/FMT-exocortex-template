#!/usr/bin/env bash
# Exocortex Update — pull upstream changes from FMT-exocortex-template
# Targets: Linux, macOS
#
# Использование:
#   update.sh              # fetch + merge + reinstall platform-space
#   update.sh --check      # только проверить, есть ли обновления
#   update.sh --dry-run    # показать что изменится, не применять
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR

# shellcheck source=lib/lib-env.sh
source "${SCRIPT_DIR}/lib/lib-env.sh"

# shellcheck source=lib/lib-platform.sh
source "${SCRIPT_DIR}/lib/lib-platform.sh"

# shellcheck source=update/lib/lib-upstream.sh
source "${SCRIPT_DIR}/update/lib/lib-upstream.sh"

# shellcheck source=update/lib/lib-refresh.sh
source "${SCRIPT_DIR}/update/lib/lib-refresh.sh"

REPO_ROOT="$(iwe_find_repo_root "${SCRIPT_DIR}" 2>/dev/null || printf '%s' "${SCRIPT_DIR}")"
readonly REPO_ROOT

ENV_FILE="$(iwe_env_file_from_repo_root "${REPO_ROOT}")"
readonly ENV_FILE

# --- Определить рабочую директорию ---
# Скрипт должен запускаться из корня форка экзокортекса
if [ -f "$REPO_ROOT/CLAUDE.md" ] && [ -d "$REPO_ROOT/memory" ]; then
    EXOCORTEX_DIR="$REPO_ROOT"
else
    echo "ERROR: Cannot find exocortex directory."
    echo "Run this script from your exocortex fork root:"
    echo "  cd /path/to/your-exocortex && bash update.sh"
    exit 1
fi

# Load IWE env
iwe_load_env_file "${ENV_FILE}" || exit 1

WORKSPACE_DIR="$(dirname "$EXOCORTEX_DIR")"
DRY_RUN=false
CHECK_ONLY=false

case "${1:-}" in
    --dry-run)   DRY_RUN=true ;;
    --check)     CHECK_ONLY=true ;;
esac

exo_print_update_banner "$EXOCORTEX_DIR"

cd "$EXOCORTEX_DIR"

exo_ensure_upstream_remote
if ! exo_check_upstream_status; then
    status=$?
    if [[ "$status" -eq 10 ]]; then
        exit 0
    fi
    exit "$status"
fi

if $CHECK_ONLY; then
    echo "Run 'update.sh' to apply these changes."
    exit 0
fi

exo_merge_upstream "$DRY_RUN" || exit 1
exo_refresh_placeholders "$DRY_RUN" "$EXOCORTEX_DIR" "$WORKSPACE_DIR"
exo_show_release_notes "$EXOCORTEX_DIR"
exo_reinstall_platform_space "$DRY_RUN" "$EXOCORTEX_DIR" "$WORKSPACE_DIR"
exo_reinstall_changed_roles "$DRY_RUN" "$EXOCORTEX_DIR"
exo_finish_update "$DRY_RUN"
