#!/usr/bin/env bash
# Adapter: File log
# Always enabled — writes to ~/.local/state/logs/notify/
# Targets: inherited from caller

adapter_enabled() { return 0; }

adapter_min_level() { printf 'info'; }

adapter_send() {
  local title="${1}"
  local message="${2}"
  local log_dir="${HOME}/.local/state/logs/notify"
  local log_file="${log_dir}/$(date +%Y-%m-%d).log"
  mkdir -p "${log_dir}"
  printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${title}" "${message}" >> "${log_file}"
}
