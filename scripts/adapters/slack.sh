#!/usr/bin/env bash
# Adapter: Slack (placeholder)
# Requires: SLACK_WEBHOOK_URL env var
# Targets: inherited from caller

adapter_enabled() {
  [[ -n "${SLACK_WEBHOOK_URL:-}" ]]
}

adapter_min_level() { printf 'notice'; }

adapter_send() {
  printf 'Slack adapter not implemented\n' >&2
  return 1
}
