#!/usr/bin/env bash
# Adapter: Email (placeholder)
# Requires: IWE_EMAIL_TO env var
# Targets: inherited from caller

adapter_enabled() {
  [[ -n "${IWE_EMAIL_TO:-}" ]]
}

adapter_min_level() { printf 'critical'; }

adapter_send() {
  printf 'Email adapter not implemented\n' >&2
  return 1
}
