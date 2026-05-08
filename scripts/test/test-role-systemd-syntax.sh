#!/usr/bin/env bash
# test-role-systemd-syntax.sh — валидация systemd service/timer файлов
# Source: roles/*/scripts/systemd/*.{service,timer} (8 files)
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- systemd service files ---"
svc_files=$(find "$ROOT_DIR/roles" -name "*.service" -type f 2>/dev/null || true)
svc_count=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  name="${f#$ROOT_DIR/}"
  svc_count=$((svc_count + 1))
  has_unit=$(grep -c '^\[Unit\]' "$f" 2>/dev/null || echo 0)
  has_service=$(grep -c '^\[Service\]' "$f" 2>/dev/null || echo 0)
  has_exec=$(grep -c '^ExecStart=' "$f" 2>/dev/null || echo 0)
  if [ "$has_service" -gt 0 ] && [ "$has_exec" -gt 0 ]; then
    _pass "$name: [Service] + ExecStart"
  else
    _fail "$name: missing [Service] or ExecStart"
  fi
done <<< "$svc_files"
echo "  service files: $svc_count checked"

echo "  --- systemd timer files ---"
timer_files=$(find "$ROOT_DIR/roles" -name "*.timer" -type f 2>/dev/null || true)
timer_count=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  name="${f#$ROOT_DIR/}"
  timer_count=$((timer_count + 1))
  has_unit=$(grep -c '^\[Unit\]' "$f" 2>/dev/null || echo 0)
  has_timer=$(grep -c '^\[Timer\]' "$f" 2>/dev/null || echo 0)
  has_calendar=$(grep -cE '^OnCalendar=|^OnUnitActiveSec=' "$f" 2>/dev/null || echo 0)
  if [ "$has_timer" -gt 0 ] && [ "$has_calendar" -gt 0 ]; then
    _pass "$name: [Timer] + schedule key"
  else
    _fail "$name: missing [Timer] or schedule key"
  fi
done <<< "$timer_files"
echo "  timer files: $timer_count checked"

echo "  --- Description= check ---"
all_unit_files=$(find "$ROOT_DIR/roles" -name "*.service" -o -name "*.timer" 2>/dev/null | sort)
desc_ok=0 desc_total=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  name="${f#$ROOT_DIR/}"
  desc_total=$((desc_total + 1))
  grep -q '^Description=' "$f" 2>/dev/null && desc_ok=$((desc_ok + 1))
done <<< "$all_unit_files"
[ "$desc_ok" -eq "$desc_total" ] \
  && _pass "Description=: $desc_ok/$desc_total" \
  || _fail "Description=: $desc_ok/$desc_total"

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL
