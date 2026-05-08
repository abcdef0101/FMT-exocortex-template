#!/usr/bin/env bash
# test-role-timer-consistency.sh — pairing: timer ↔ service
# Source: roles/*/scripts/systemd/*.{service,timer}
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- timer → service pairing ---"
timer_files=$(find "$ROOT_DIR/roles" -name "*.timer" -type f 2>/dev/null || true)
svc_files=$(find "$ROOT_DIR/roles" -name "*.service" -type f 2>/dev/null || true)

unpaired=0
while IFS= read -r timer; do
  [ -z "$timer" ] && continue
  timer_name=$(basename "$timer" .timer)
  matching=$(echo "$svc_files" | grep "$timer_name.service" || true)
  if [ -n "$matching" ]; then
    _pass "$timer_name: paired with service"
  else
    _fail "$timer_name: no matching .service file"
    unpaired=$((unpaired + 1))
  fi
done <<< "$timer_files"

echo "  --- standalone services (no timer) ---"
while IFS= read -r svc; do
  [ -z "$svc" ] && continue
  svc_name=$(basename "$svc" .service)
  matching=$(echo "$timer_files" | grep "$svc_name.timer" || true)
  if [ -z "$matching" ]; then
    echo "  • $svc_name: standalone service (no timer — may be oneshot or manual)"
  fi
done <<< "$svc_files"

echo "  --- naming convention ---"
naming_ok=0 naming_total=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  name=$(basename "$f")
  naming_total=$((naming_total + 1))
  if [[ "$name" =~ ^exocortex- ]]; then
    naming_ok=$((naming_ok + 1))
  fi
done <<< "$timer_files"
while IFS= read -r f; do
  [ -z "$f" ] && continue
  name=$(basename "$f")
  naming_total=$((naming_total + 1))
  if [[ "$name" =~ ^exocortex- ]]; then
    naming_ok=$((naming_ok + 1))
  fi
done <<< "$svc_files"

[ "$naming_ok" -eq "$naming_total" ] \
  && _pass "naming: $naming_ok/$naming_total exocortex- prefix" \
  || _fail "naming: $naming_ok/$naming_total exocortex- prefix"

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL
