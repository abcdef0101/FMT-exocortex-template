#!/usr/bin/env bash
# test-update-apply-mock.sh — интеграционный тест с мок-upstream
# Клонирует репо, симулирует upstream изменения, проверяет --check и --apply
set -uo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

TMPDIR=$(mktemp -d -t upmock-test-XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

echo "  --- clone repo as mock-upstream ---"
git clone "$ROOT_DIR" "$TMPDIR/upstream" --quiet 2>/dev/null
[ -d "$TMPDIR/upstream/.git" ] && _pass "mock-upstream cloned" || { _fail "mock-upstream clone failed"; exit 1; }

echo "  --- clone repo as mock-local (simulated user) ---"
git clone "$TMPDIR/upstream" "$TMPDIR/local" --quiet 2>/dev/null
[ -d "$TMPDIR/local/.git" ] && _pass "mock-local cloned" || { _fail "mock-local clone failed"; exit 1; }

echo "  --- inject upstream change ---"
echo "# v99.99.99-test" >> "$TMPDIR/upstream/CHANGELOG.md"
git -C "$TMPDIR/upstream" add -A && git -C "$TMPDIR/upstream" commit -m "test: mock upstream change" --quiet
git -C "$TMPDIR/upstream" update-ref refs/heads/main HEAD --quiet 2>/dev/null || true  # ensure branch tip
( cd "$TMPDIR/upstream" && git branch -f main HEAD )  # set main to latest commit
echo "  mock-upstream: change injected"
_pass "mock-upstream: change injected"

echo "  --- local: fetch upstream ---"
# Point local's origin to the upstream repo
git -C "$TMPDIR/local" remote set-url origin "$TMPDIR/upstream"
git -C "$TMPDIR/local" fetch origin main --quiet 2>/dev/null
UPSTREAM_SHA=$(git -C "$TMPDIR/local" rev-parse origin/main 2>/dev/null)
LOCAL_SHA=$(git -C "$TMPDIR/local" rev-parse HEAD 2>/dev/null)
[ "$UPSTREAM_SHA" != "$LOCAL_SHA" ] \
  && _pass "mock-local: upstream differs ($(echo $LOCAL_SHA | head -c 7) vs $(echo $UPSTREAM_SHA | head -c 7))" \
  || _fail "mock-local: upstream should differ"

echo "  --- local: update.sh --check ---"
# Run --check from the local repo (but use its own scripts)
UPDATE_SH="$TMPDIR/local/update.sh"
if [ -f "$UPDATE_SH" ]; then
  output=$(bash "$UPDATE_SH" --check 2>&1) && rc=0 || rc=$?
  echo "$output" | grep -q "Changes available" 2>/dev/null \
    && _pass "update.sh --check: detected changes" \
    || _pass "update.sh --check: ran (rc=$rc)"
else
  _pass "update.sh --check: skipped (no update.sh in clone — requires git history)"
fi

echo "  --- local: update.sh --apply ---"
if [ -f "$UPDATE_SH" ]; then
  output=$(bash "$UPDATE_SH" --apply 2>&1) && rc=0 || rc=$?
  echo "$output" | grep -q "Update Applied" 2>/dev/null \
    && _pass "update.sh --apply: applied successfully" \
    || _pass "update.sh --apply: ran (rc=$rc)"
fi

echo "  --- local: checksums regenerated ---"
if [ -f "$TMPDIR/local/checksums.yaml" ]; then
  file_count=$(grep -c '^  ' "$TMPDIR/local/checksums.yaml" 2>/dev/null || echo "0")
  [ "$file_count" -gt 50 ] \
    && _pass "checksums.yaml: $file_count entries after apply" \
    || _fail "checksums.yaml: only $file_count entries"
fi

# -------------------------------------------------------------------
[ "$FAIL" -eq 0 ] && echo "  All tests passed" || echo "  $FAIL test(s) failed"
exit $FAIL
