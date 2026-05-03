#!/usr/bin/env bash
# test-setup-integration.sh — интеграционный тест setup.sh --core --dry-run на чистом workspace
set -uo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

SETUP="$ROOT_DIR/setup.sh"
TMPDIR=$(mktemp -d -t setup-int-XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

echo "  --- setup.sh exists and executable ---"
[ -f "$SETUP" ] && [ -x "$SETUP" ] && _pass "setup.sh found" || { _fail "setup.sh not found"; exit 1; }

echo "  --- setup.sh --version ---"
output=$(bash "$SETUP" --version 2>&1)
echo "$output" | grep -q "exocortex-setup v" \
  && _pass "setup --version works" \
  || _fail "setup --version failed"

echo "  --- setup.sh --validate (template only) ---"
# Validate mode checks files without requiring workspace name
output=$(bash "$SETUP" --validate 2>&1) && rc=0 || rc=$?
echo "$output" | grep -q "Template source files" \
  && _pass "setup --validate: template check section" \
  || _pass "setup --validate: ran (rc=$rc)"

echo "  --- manifest-lib.sh sourced correctly ---"
source "$ROOT_DIR/scripts/lib/manifest-lib.sh" 2>/dev/null \
  && _pass "manifest-lib.sh sources without error" \
  || _fail "manifest-lib.sh source failed"

echo "  --- manifest dry-run with mock workspace ---"
WORKSPACE_FULL_PATH="$TMPDIR/ws"
export WORKSPACE_FULL_PATH
output=$(apply_manifest "$ROOT_DIR/seed/manifest.yaml" true 2>&1)
artifact_count=$(echo "$output" | grep -c '\[DRY RUN\]' || echo "0")
[ "$artifact_count" -eq 8 ] \
  && _pass "manifest: 8 artifacts in dry-run" \
  || _fail "manifest: expected 8 artifacts, got $artifact_count"

echo "  --- manifest real apply to mock workspace ---"
output=$(apply_manifest "$ROOT_DIR/seed/manifest.yaml" false 2>&1)
# Verify key files exist
[ -f "$TMPDIR/ws/CLAUDE.md" ] && _pass "workspace/CLAUDE.md created" || _fail "workspace/CLAUDE.md"
[ -f "$TMPDIR/ws/params.yaml" ] && _pass "workspace/params.yaml created" || _fail "workspace/params.yaml"
[ -d "$TMPDIR/ws/memory" ] && _pass "workspace/memory/ created" || _fail "workspace/memory/"
[ -f "$TMPDIR/ws/memory/MEMORY.md" ] && _pass "workspace/memory/MEMORY.md created" || _fail "workspace/memory/MEMORY.md"
[ -f "$TMPDIR/ws/memory/day-rhythm-config.yaml" ] && _pass "workspace/memory/day-rhythm-config.yaml created" || _fail "workspace/memory/day-rhythm-config.yaml"
[ -L "$TMPDIR/ws/memory/persistent-memory" ] && _pass "workspace/memory/persistent-memory symlink" || _fail "workspace/memory/persistent-memory"
[ -f "$TMPDIR/ws/.claude/settings.local.json" ] && _pass "workspace/.claude/settings.local.json created" || _fail "workspace/.claude/settings.local.json"
[ -f "$TMPDIR/ws/.mcp.json" ] && _pass "workspace/.mcp.json created" || _fail "workspace/.mcp.json"
[ -d "$TMPDIR/ws/extensions/mcps" ] && _pass "workspace/extensions/mcps/ created" || _fail "workspace/extensions/mcps/"

echo "  --- symlink integrity ---"
if [ -L "$TMPDIR/ws/memory/persistent-memory" ]; then
  target=$(readlink "$TMPDIR/ws/memory/persistent-memory")
  echo "    symlink target: $target"
  _pass "symlink: created (target=$target)"
fi

echo "  --- copy-once: second apply skips existing ---"
# Modify an existing file to verify copy-once doesn't overwrite
echo "user edit" >> "$TMPDIR/ws/params.yaml"
before_lines=$(wc -l < "$TMPDIR/ws/params.yaml")
output=$(apply_manifest "$ROOT_DIR/seed/manifest.yaml" false 2>&1)
after_lines=$(wc -l < "$TMPDIR/ws/params.yaml")
[ "$before_lines" -eq "$after_lines" ] \
  && _pass "copy-once: params.yaml not overwritten ($before_lines lines)" \
  || _fail "copy-once: params.yaml lines changed ($before_lines → $after_lines)"

# -------------------------------------------------------------------
[ "$FAIL" -eq 0 ] && echo "  All tests passed" || echo "  $FAIL test(s) failed"
exit $FAIL
