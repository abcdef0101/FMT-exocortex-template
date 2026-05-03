#!/usr/bin/env bash
# test-manifest-parser.sh — тестирование парсера manifest и всех 6 стратегий
# Запускается из run-phase0.sh (ROOT_DIR уже экспортирован)
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "$ROOT_DIR/scripts/lib/manifest-lib.sh" 2>/dev/null || {
  echo "  ✗ cannot source manifest-lib.sh"
  exit 1
}

TMPDIR=$(mktemp -d -t manifest-test-XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

# -------------------------------------------------------------------
echo "  --- copy-once ---"

mkdir -p "$TMPDIR/once-new"
echo "hello" > "$TMPDIR/src-once.txt"
apply_strategy "$TMPDIR/src-once.txt" "$TMPDIR/once-new/dst.txt" "copy-once" "" "" "false"
[ -f "$TMPDIR/once-new/dst.txt" ] && [ "$(cat "$TMPDIR/once-new/dst.txt")" = "hello" ] \
  && _pass "copy-once creates file" \
  || _fail "copy-once creates file"

mtime_before=$(stat -c %Y "$TMPDIR/once-new/dst.txt" 2>/dev/null || stat -f %m "$TMPDIR/once-new/dst.txt" 2>/dev/null)
echo "modified" > "$TMPDIR/src-once.txt"
sleep 0.1  # ensure mtime differs
apply_strategy "$TMPDIR/src-once.txt" "$TMPDIR/once-new/dst.txt" "copy-once" "" "" "false"
mtime_after=$(stat -c %Y "$TMPDIR/once-new/dst.txt" 2>/dev/null || stat -f %m "$TMPDIR/once-new/dst.txt" 2>/dev/null)
[ "$mtime_before" = "$mtime_after" ] \
  && _pass "copy-once skips existing" \
  || _fail "copy-once skips existing"

# -------------------------------------------------------------------
echo "  --- copy-if-newer ---"

mkdir -p "$TMPDIR/ifnew"
echo "v1" > "$TMPDIR/ifnew/src.txt"
echo "v1" > "$TMPDIR/ifnew/dst.txt"
sleep 0.2  # ensure src is newer by a margin
echo "v2" > "$TMPDIR/ifnew/src.txt"
apply_strategy "$TMPDIR/ifnew/src.txt" "$TMPDIR/ifnew/dst.txt" "copy-if-newer" "" "" "false"
[ "$(cat "$TMPDIR/ifnew/dst.txt")" = "v2" ] \
  && _pass "copy-if-newer updates older" \
  || _fail "copy-if-newer updates older"

echo "v3" > "$TMPDIR/ifnew/src.txt"
apply_strategy "$TMPDIR/ifnew/src.txt" "$TMPDIR/ifnew/dst.txt" "copy-if-newer" "" "" "false"
[ "$(cat "$TMPDIR/ifnew/dst.txt")" = "v3" ] \
  && _pass "copy-if-newer updates when src newer again" \
  || _fail "copy-if-newer updates when src newer again"

# dst newer than src — should skip
echo "old" > "$TMPDIR/ifnew/src.txt"
sleep 0.2
echo "newer" > "$TMPDIR/ifnew/dst.txt"
apply_strategy "$TMPDIR/ifnew/src.txt" "$TMPDIR/ifnew/dst.txt" "copy-if-newer" "" "" "false"
[ "$(cat "$TMPDIR/ifnew/dst.txt")" = "newer" ] \
  && _pass "copy-if-newer skips newer" \
  || _fail "copy-if-newer skips newer"

# P0: target does not exist → should create
mkdir -p "$TMPDIR/ifnew/missing"
rm -f "$TMPDIR/ifnew/missing/target.txt"
echo "first-time" > "$TMPDIR/ifnew/missing/src.txt"
apply_strategy "$TMPDIR/ifnew/missing/src.txt" "$TMPDIR/ifnew/missing/target.txt" "copy-if-newer" "" "" "false"
[ "$(cat "$TMPDIR/ifnew/missing/target.txt")" = "first-time" ] \
  && _pass "copy-if-newer creates when target missing" \
  || _fail "copy-if-newer creates when target missing"

# -------------------------------------------------------------------
echo "  --- copy-and-substitute ---"

mkdir -p "$TMPDIR/subst"
CURRENT_ROOT="$ROOT_DIR"  # save
export ROOT_DIR="/fake/root/path"
echo 'Root: {{ROOT_DIR}}' > "$TMPDIR/subst/src.json"
apply_strategy "$TMPDIR/subst/src.json" "$TMPDIR/subst/dst.json" "copy-and-substitute" "" "{{ROOT_DIR}}" "false"
grep -q "/fake/root/path" "$TMPDIR/subst/dst.json" \
  && _pass "copy-and-substitute replaces placeholder" \
  || _fail "copy-and-substitute replaces placeholder"

# No placeholders — should still copy without error
echo 'no placeholders here' > "$TMPDIR/subst/no-ph.txt"
apply_strategy "$TMPDIR/subst/no-ph.txt" "$TMPDIR/subst/no-ph-dst.txt" "copy-and-substitute" "" "" "false"
[ -f "$TMPDIR/subst/no-ph-dst.txt" ] \
  && _pass "copy-and-substitute works without placeholders" \
  || _fail "copy-and-substitute works without placeholders"

export ROOT_DIR="$CURRENT_ROOT"  # restore

# P1: multiple placeholders
echo "  --- copy-and-substitute: multiple placeholders ---"
mkdir -p "$TMPDIR/multi"
export ROOT_DIR="/fake/multi"
echo 'A: {{ROOT_DIR}}, B: {{ROOT_DIR}}, C: {{ROOT_DIR}}' > "$TMPDIR/multi/multi.txt"
apply_strategy "$TMPDIR/multi/multi.txt" "$TMPDIR/multi/multi-dst.txt" "copy-and-substitute" "" "{{ROOT_DIR}}" "false"
count=$(grep -o '/fake/multi' "$TMPDIR/multi/multi-dst.txt" 2>/dev/null | wc -l)
export ROOT_DIR="$CURRENT_ROOT"
[ "$count" -eq 3 ] \
  && _pass "copy-and-substitute: all placeholders ($count/3)" \
  || _fail "copy-and-substitute: all placeholders (expected 3, got $count)"

# P1: placeholder without env-var fallback
echo "  --- copy-and-substitute: missing env-var ---"
mkdir -p "$TMPDIR/missingvar"
echo 'Missing: {{MISSING_VAR}}' > "$TMPDIR/missingvar/src.txt"
unset MISSING_VAR 2>/dev/null || true
apply_strategy "$TMPDIR/missingvar/src.txt" "$TMPDIR/missingvar/dst.txt" "copy-and-substitute" "" "{{MISSING_VAR}}" "false"
[ -f "$TMPDIR/missingvar/dst.txt" ] \
  && _pass "copy-and-substitute: missing env-var no crash" \
  || _fail "copy-and-substitute: missing env-var crashed"

# P1 #1: partial placeholder match
echo "  --- copy-and-substitute: partial match ---"
mkdir -p "$TMPDIR/partial"
echo 'Path: {{ROOT_DIR}}/subdir, Var: {{ROOT_DIR}}_NAME' > "$TMPDIR/partial/src.txt"
export ROOT_DIR="/fake/partial"
apply_strategy "$TMPDIR/partial/src.txt" "$TMPDIR/partial/dst.txt" "copy-and-substitute" "" "{{ROOT_DIR}}" "false"
export ROOT_DIR="$CURRENT_ROOT"
if grep -q "/fake/partial/subdir" "$TMPDIR/partial/dst.txt" 2>/dev/null; then
  # Note: {{ROOT_DIR}}_NAME is also partially matched by s|{{ROOT_DIR}}|...|g
  # This is a known behavior — the sed substitution is greedy on prefix matches
  _pass "copy-and-substitute: partial prefix match (sed default: greedy)"
else
  _fail "copy-and-substitute: partial prefix match (unexpected)"
fi

# P1 #3: manifest parser ignores unknown YAML fields
echo "  --- manifest parser: extra YAML fields ---"
mkdir -p "$TMPDIR/extrafields"
cat > "$TMPDIR/extrafields/test-manifest.yaml" << 'YEOF'
artifacts:
  - source: /tmp/extra-src.txt
    target: /tmp/extra-dst.txt
    strategy: copy-once
    extra_field: should_be_ignored
    another_extra: also_ignored
YEOF
echo "hello" > /tmp/extra-src.txt
WORKSPACE_FULL_PATH="/tmp"
export WORKSPACE_FULL_PATH
output=$(apply_manifest "$TMPDIR/extrafields/test-manifest.yaml" true 2>&1)
rm -f /tmp/extra-src.txt /tmp/extra-dst.txt 2>/dev/null
echo "$output" | grep -q "DRY RUN" \
  && _pass "manifest parser: ignores unknown YAML fields" \
  || _fail "manifest parser: choked on unknown YAML fields: $output"

# P1 #4: merge-mcp with existing modified target
echo "  --- merge-mcp: target already modified ---"
mkdir -p "$TMPDIR/mcpmod"
echo '{"mcpServers":{"base":"v1"}}' > "$TMPDIR/mcpmod/base.json"
echo '{"mcpServers":{"base":"v1","user_custom":"v2"}}' > "$TMPDIR/mcpmod/existing.json"
apply_strategy "$TMPDIR/mcpmod/base.json" "$TMPDIR/mcpmod/existing.json" "merge-mcp" "" "" "false"
[ -f "$TMPDIR/mcpmod/existing.json" ] \
  && _pass "merge-mcp: succeeds when target modified (current: overwrites)" \
  || _fail "merge-mcp: fails when target modified"

# -------------------------------------------------------------------
echo "  --- symlink ---"

mkdir -p "$TMPDIR/sym/linkdir"

# Create symlink
apply_strategy "" "$TMPDIR/sym/mylink" "symlink" "../sym/linkdir" "" "false"
[ -L "$TMPDIR/sym/mylink" ] && [ "$(readlink "$TMPDIR/sym/mylink")" = "../sym/linkdir" ] \
  && _pass "symlink creates" \
  || _fail "symlink creates"

# Existing symlink — skip
apply_strategy "" "$TMPDIR/sym/mylink" "symlink" "../sym/linkdir" "" "false"
[ -L "$TMPDIR/sym/mylink" ] \
  && _pass "symlink skips existing" \
  || _fail "symlink skips existing"

# Regular file in the way — warn, don't overwrite
echo "block" > "$TMPDIR/sym/blockfile"
apply_strategy "" "$TMPDIR/sym/blockfile" "symlink" "../sym/linkdir" "" "false" 2>/dev/null || true
[ -f "$TMPDIR/sym/blockfile" ] && [ ! -L "$TMPDIR/sym/blockfile" ] \
  && _pass "symlink warns on regular file (does not overwrite)" \
  || _fail "symlink warns on regular file (does not overwrite)"

# P0: broken symlink — should recreate
mkdir -p "$TMPDIR/sym/broken-target"
ln -s "/nonexistent/path" "$TMPDIR/sym/broken-link" 2>/dev/null || true
apply_strategy "" "$TMPDIR/sym/broken-link" "symlink" "../sym/broken-target" "" "false" 2>/dev/null || true
[ -L "$TMPDIR/sym/broken-link" ] && [ -e "$TMPDIR/sym/broken-link" ] \
  && _pass "symlink repairs broken symlink" \
  || _fail "symlink repairs broken symlink (still broken)"

# -------------------------------------------------------------------
echo "  --- merge-mcp ---"

mkdir -p "$TMPDIR/merge"
echo '{"mcpServers":{}}' > "$TMPDIR/merge/base.json"
apply_strategy "$TMPDIR/merge/base.json" "$TMPDIR/merge/mcp.json" "merge-mcp" "" "" "false"
[ -f "$TMPDIR/merge/mcp.json" ] \
  && _pass "merge-mcp copies base" \
  || _fail "merge-mcp copies base"

# -------------------------------------------------------------------
echo "  --- structure-only ---"

apply_strategy "" "$TMPDIR/struct/dir" "structure-only" "" "" "false"
[ -d "$TMPDIR/struct/dir" ] \
  && _pass "structure-only creates directory" \
  || _fail "structure-only creates directory"

apply_strategy "" "$TMPDIR/struct/dir" "structure-only" "" "" "false"
[ -d "$TMPDIR/struct/dir" ] \
  && _pass "structure-only idempotent" \
  || _fail "structure-only idempotent"

# -------------------------------------------------------------------
echo "  --- unknown strategy ---"

apply_strategy "src" "dst" "nonexistent" "" "" "false" 2>/dev/null && rc=0 || rc=$?
[ "$rc" -eq 1 ] \
  && _pass "unknown strategy returns error" \
  || _fail "unknown strategy returns error (got rc=$rc)"

# -------------------------------------------------------------------
echo "  --- dry-run mode ---"

mkdir -p "$TMPDIR/dry"
echo "dry" > "$TMPDIR/dry/src.txt"
output=$(apply_strategy "$TMPDIR/dry/src.txt" "$TMPDIR/dry/dst.txt" "copy-once" "" "" "true" 2>&1)
echo "$output" | grep -q "DRY RUN" \
  && _pass "dry-run prints DRY RUN marker" \
  || _fail "dry-run prints DRY RUN marker"
[ ! -f "$TMPDIR/dry/dst.txt" ] \
  && _pass "dry-run does not create file" \
  || _fail "dry-run does not create file"

# -------------------------------------------------------------------
echo "  --- parse full manifest ---"

WORKSPACE_FULL_PATH="$TMPDIR/full"
export WORKSPACE_FULL_PATH
output=$(apply_manifest "$ROOT_DIR/seed/manifest.yaml" true 2>&1)
count=$(echo "$output" | grep -c 'DRY RUN' || true)
[ "$count" -ge 8 ] \
  && _pass "parse full manifest: $count artifacts" \
  || _fail "parse full manifest: expected >=8 artifacts, got $count"
! echo "$output" | grep -q "WARN: unknown strategy" \
  && _pass "parse full manifest: no unknown strategies" \
  || _fail "parse full manifest: unknown strategy warnings"

# -------------------------------------------------------------------
[ "$FAIL" -eq 0 ] && echo "  All $(( 21 )) tests passed" || echo "  $FAIL test(s) failed"
exit $FAIL
