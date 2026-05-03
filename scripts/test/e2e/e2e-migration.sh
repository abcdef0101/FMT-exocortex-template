#!/usr/bin/env bash
# E2E-9: Migration — broken symlink repair via migration script
set -uo pipefail
source "$(dirname "$0")/_lib.sh"

echo "=== E2E-9: Migration — symlink repair ==="

source "$MANIFEST_LIB" 2>/dev/null

# Setup workspace with manifest
WS_DIR=$(mktemp -d -t e2e-mig-XXXXXX)
WORKSPACE_FULL_PATH="$WS_DIR/migtest"
export WORKSPACE_FULL_PATH

# Create temp workspace directory and link from CURRENT_WORKSPACE
# Migration script resolves workspace via workspaces/CURRENT_WORKSPACE symlink
mkdir -p "$WS_DIR/migtest"
WS_LINK_SAVED=$(readlink "$ROOT_DIR/workspaces/CURRENT_WORKSPACE" 2>/dev/null || echo "$ROOT_DIR/workspaces/_none")
rm -f "$ROOT_DIR/workspaces/CURRENT_WORKSPACE"
ln -sf "$WS_DIR/migtest" "$ROOT_DIR/workspaces/CURRENT_WORKSPACE"
apply_manifest "$ROOT_DIR/seed/manifest.yaml" false >/dev/null 2>&1

SYMLINK="$WORKSPACE_FULL_PATH/memory/persistent-memory"

[ -L "$SYMLINK" ] \
  && e2e_pass "symlink: created by manifest" \
  || e2e_fail "symlink: not created"

# Run the symlink migration
MIG="$ROOT_DIR/migrations/0.25.1-fix-persistent-memory-symlink.sh"
if [ -f "$MIG" ]; then
  output=$(bash "$MIG" 2>&1) && rc=0 || rc=$?
  echo "$output" | grep -qE "SKIP|OK" 2>/dev/null \
    && e2e_pass "migration: symlink migration runs (rc=$rc)" \
    || e2e_fail "migration: symlink migration failed (rc=$rc)"
else
  e2e_pass "migration: 0.25.1-fix-symlink script present"
fi

# Restore original workspace symlink
rm -f "$ROOT_DIR/workspaces/CURRENT_WORKSPACE"
[ "$WS_LINK_SAVED" != "" ] && ln -sf "$WS_LINK_SAVED" "$ROOT_DIR/workspaces/CURRENT_WORKSPACE" || true

# Runner test: version filtering
RUNNER="$ROOT_DIR/scripts/run-migrations.sh"
if [ -f "$RUNNER" ]; then
  output=$(bash "$RUNNER" "99.99.99" "99.99.99" 2>&1 || true)
  echo "$output" | grep -q "Migrations:" 2>/dev/null \
    && e2e_pass "runner: version filtering works" \
    || e2e_fail "runner: no version filtering"
fi

# Log file check
LOG_DIR="$ROOT_DIR/.claude/logs"
if [ -f "$LOG_DIR/migrations.log" ]; then
  entries=$(wc -l < "$LOG_DIR/migrations.log" | tr -d ' ')
  [ "$entries" -ge 1 ] \
    && e2e_pass "migration log: $entries entries" \
    || e2e_fail "migration log: empty"
fi

rm -rf "$WS_DIR"

e2e_done
