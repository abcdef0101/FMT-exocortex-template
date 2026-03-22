#!/usr/bin/env bash
# notify.sh — Observer dispatcher уведомлений экзокортекса
# Interface: notify.sh <title> <message> [level=info]
# Levels:    info(0) < notice(1) < alert(2) < critical(3)
# Adapters:  scripts/adapters/*.sh (auto-discovered)
# Targets: Linux, macOS

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ADAPTERS_DIR="${SCRIPT_DIR}/adapters"

# shellcheck source=lib/lib-env.sh
source "${SCRIPT_DIR}/../lib/lib-env.sh"

TITLE="${1:?Ошибка: укажи заголовок (title)}"
MESSAGE="${2:?Ошибка: укажи тело сообщения (message)}"
LEVEL="${3:-info}"

if _repo_root="$(iwe_find_repo_root "${SCRIPT_DIR}" 2>/dev/null)"; then
  ENV_FILE="$(iwe_env_file_from_repo_root "${_repo_root}")"
  iwe_load_env_file "${ENV_FILE}" || true
fi
unset _repo_root

_iwe_level_to_int() {
  case "${1}" in
    info)     printf '0' ;;
    notice)   printf '1' ;;
    alert)    printf '2' ;;
    critical) printf '3' ;;
    *)
      printf 'WARN: unknown notify level "%s", using info\n' "${1}" >&2
      printf '0'
      ;;
  esac
}

_LEVEL_INT="$(_iwe_level_to_int "${LEVEL}")"
_dispatched=0

for _adapter_file in "${ADAPTERS_DIR}"/*.sh; do
  [[ -f "${_adapter_file}" ]] || continue
  _dispatched=$((_dispatched + 1))
  (
    # shellcheck source=/dev/null
    source "${_adapter_file}"
    adapter_enabled || exit 0
    _min_int="$(_iwe_level_to_int "$(adapter_min_level)")"
    [[ "${_LEVEL_INT}" -ge "${_min_int}" ]] || exit 0
    adapter_send "${TITLE}" "${MESSAGE}"
  ) || true
done

if [[ "${_dispatched}" -eq 0 ]]; then
  printf 'WARN: No adapters found in %s\n' "${ADAPTERS_DIR}" >&2
fi
