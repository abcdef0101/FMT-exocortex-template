#!/usr/bin/env bash
# test-migrations.sh — тесты миграционного фреймворка
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

MIG_DIR="$ROOT_DIR/migrations"
RUNNER="$ROOT_DIR/scripts/run-migrations.sh"
TMPDIR=$(mktemp -d -t mig-test-XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

echo "  --- framework files exist ---"
[ -f "$MIG_DIR/README.md" ] && _pass "migrations/README.md" || _fail "migrations/README.md"
[ -f "$MIG_DIR/_template.sh" ] && _pass "migrations/_template.sh" || _fail "migrations/_template.sh"
[ -f "$RUNNER" ] && _pass "scripts/run-migrations.sh" || _fail "scripts/run-migrations.sh"

echo "  --- real migrations exist ---"
mig_count=$(find "$MIG_DIR" -name "*.sh" -not -name "_template.sh" | wc -l)
[ "$mig_count" -ge 3 ] \
  && _pass "real migrations: $mig_count scripts" \
  || _fail "real migrations: expected >=3, got $mig_count"

echo "  --- migration syntax ---"
syn_ok=0 syn_fail=0
while IFS= read -r -d '' script; do
  if bash -n "$script" 2>/dev/null; then
    syn_ok=$((syn_ok + 1))
  else
    _fail "syntax error: $(basename "$script")"
    syn_fail=$((syn_fail + 1))
  fi
done < <(find "$MIG_DIR" -name "*.sh" -not -name "_template.sh" -print0)
[ "$syn_fail" -eq 0 ] && _pass "syntax: $syn_ok/$syn_ok ok" || true

echo "  --- migration conventions ---"
while IFS= read -r -d '' script; do
  name=$(basename "$script")
  [[ "$name" == "_template.sh" ]] && continue
  # Naming: {version}-{component}-{description}.sh
  if [[ "$name" =~ ^[0-9]+\.[0-9]+\.[0-9]+-.+\.sh$ ]]; then
    :
  else
    _fail "naming convention: $name"
  fi

  # Must have MIGRATION_NAME
  grep -q "MIGRATION_NAME=" "$script" \
    || _fail "no MIGRATION_NAME: $name"

  # Must have LOG_FILE
  grep -q "LOG_FILE" "$script" \
    || _fail "no LOG_FILE: $name"

  # Must have pre-condition skip OR be informational-only
  if grep -qE "(SKIP|_log.*INFO|documented|manual)" "$script" 2>/dev/null; then
    :
  else
    _fail "no skip/info condition: $name"
  fi
done < <(find "$MIG_DIR" -name "*.sh" -not -name "_template.sh" -print0)
echo "  ✓ conventions verified for $mig_count migrations"

echo "  --- runner: version filtering ---"
# Test runner with dummy versions — should skip all migrations
output=$(bash "$RUNNER" "99.99.99" "99.99.99" 2>&1 || true)
echo "$output" | grep -q "Migrations: 0 applied" \
  && _pass "runner: future local version → all skipped" \
  || _fail "runner: future local version → unexpected"

echo "  --- runner: old version allows migrations ---"
output=$(bash "$RUNNER" "0.0.0" "99.99.99" 2>&1 || true)
# Should show applied count (but real migrations may already be applied)
echo "$output" | grep -q "Migrations:" \
  && _pass "runner: old local version → processes migrations" \
  || _fail "runner: old local version → no output"

echo "  --- migration: idempotency ---"
# Run the same migration twice — second should skip
# Use fix-symlink as it's the simplest
SYMLINK_MIG="$MIG_DIR/0.25.1-fix-persistent-memory-symlink.sh"
if [ -f "$SYMLINK_MIG" ]; then
  bash "$SYMLINK_MIG" 2>/dev/null >/dev/null && rc1=$? || rc1=$?
  bash "$SYMLINK_MIG" 2>/dev/null >/dev/null && rc2=$? || rc2=$?
  # Both should succeed (skip on second)
  [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ] \
    && _pass "idempotent: symlink migration runs twice" \
    || _fail "idempotent: symlink migration failed (rc1=$rc1 rc2=$rc2)"
fi

echo "  --- runner: dedup via marker ---"
APPLIED_FILE="$ROOT_DIR/.claude/.migrations-applied"
if [ -f "$APPLIED_FILE" ]; then
  dedup_count=$(wc -l < "$APPLIED_FILE" | tr -d ' ')
  [ "$dedup_count" -ge 1 ] \
    && _pass "runner: $dedup_count entries in marker file" \
    || _fail "runner: marker file empty"
fi

# -------------------------------------------------------------------
[ "$FAIL" -eq 0 ] && echo "  All tests passed" || echo "  $FAIL test(s) failed"
exit $FAIL
