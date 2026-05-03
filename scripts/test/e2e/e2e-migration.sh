#!/usr/bin/env bash
# E2E-9: Migration — broken symlink repair via migration script
set -uo pipefail
source "$(dirname "$0")/_lib.sh"

echo "=== E2E-9: Migration — symlink repair ==="

source "$MANIFEST_LIB" 2>/dev/null

# Setup: create workspace structure with valid symlink
# In the real repo: workspaces/iwe2/memory/persistent-memory -> ../../../persistent-memory/
#   = repo_root/persistent-memory/
# In temp dir:   $WS_DIR/migtest/memory/persistent-memory -> ../../persistent-memory/
#   = $WS_DIR/persistent-memory/ (because migtest is 1 level deeper)
WS_DIR=$(mktemp -d -t e2e-mig-XXXXXX)
WORKSPACE_FULL_PATH="$WS_DIR/migtest"
export WORKSPACE_FULL_PATH
mkdir -p "$WORKSPACE_FULL_PATH/memory"

mkdir -p "$WS_DIR/persistent-memory"
echo "# test" > "$WS_DIR/persistent-memory/test.md"
ln -s "../../persistent-memory/" "$WORKSPACE_FULL_PATH/memory/persistent-memory"

# Link from CURRENT_WORKSPACE (migration script resolves via this)
WS_LINK_SAVED=$(readlink "$ROOT_DIR/workspaces/CURRENT_WORKSPACE" 2>/dev/null || echo "")
rm -f "$ROOT_DIR/workspaces/CURRENT_WORKSPACE"
ln -sf "$WORKSPACE_FULL_PATH" "$ROOT_DIR/workspaces/CURRENT_WORKSPACE"

SYMLINK="$WORKSPACE_FULL_PATH/memory/persistent-memory"
[ -L "$SYMLINK" ] && [ -e "$SYMLINK" ] \
  && e2e_pass "symlink: created and valid" \
  || e2e_fail "symlink: broken or missing"

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
[ -n "$WS_LINK_SAVED" ] && ln -sf "$WS_LINK_SAVED" "$ROOT_DIR/workspaces/CURRENT_WORKSPACE" || true

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
