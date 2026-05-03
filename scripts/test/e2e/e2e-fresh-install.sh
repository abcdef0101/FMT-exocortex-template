#!/usr/bin/env bash
# E2E-1: Fresh install — clean workspace
# E2E-2: Duplicate workspace — error
# E2E-3: Install + immediate update check
set -uo pipefail
source "$(dirname "$0")/_lib.sh"

echo "=== E2E-1: Fresh install — clean workspace ==="

# Create workspace in temp dir
WS_DIR=$(mktemp -d -t e2e-ws1-XXXXXX)
WORKSPACE_FULL_PATH="$WS_DIR/iwetest"
export WORKSPACE_FULL_PATH

# Source manifest-lib and apply manifest
source "$MANIFEST_LIB" 2>/dev/null || { e2e_fail "cannot source manifest-lib"; e2e_done; exit 1; }

# Dry-run first
output=$(apply_manifest "$ROOT_DIR/seed/manifest.yaml" true 2>&1)
echo "$output" | grep -q "DRY RUN" \
  && e2e_pass "manifest: dry-run works" \
  || e2e_fail "manifest: dry-run failed"

# Real apply
output=$(apply_manifest "$ROOT_DIR/seed/manifest.yaml" false 2>&1)
artifact_count=$(echo "$output" | grep -cE "copy-once:|copy-if-newer:|symlink created:|merge-mcp:|structure-only:|copy-and-substitute:" || echo "0")
[ "$artifact_count" -ge 7 ] \
  && e2e_pass "manifest: $artifact_count artifacts applied" \
  || e2e_fail "manifest: only $artifact_count artifacts"

# Verify structure
verify_workspace_structure "$WORKSPACE_FULL_PATH"
[ -f "$WORKSPACE_FULL_PATH/CLAUDE.md" ] && e2e_pass "CLAUDE.md: $(wc -l < "$WORKSPACE_FULL_PATH/CLAUDE.md") lines"
[ -f "$WORKSPACE_FULL_PATH/params.yaml" ] && e2e_pass "params.yaml: exists"
[ -f "$WORKSPACE_FULL_PATH/.claude/settings.local.json" ] && e2e_pass "settings.local.json: exists"
verify_symlink "$WORKSPACE_FULL_PATH"

rm -rf "$WS_DIR"

# === E2E-2 ===
echo ""
echo "=== E2E-2: Duplicate workspace — error ==="

WS_DIR=$(mktemp -d -t e2e-ws2-XXXXXX)
WORKSPACE_FULL_PATH="$WS_DIR/duptest"
export WORKSPACE_FULL_PATH

# First install
apply_manifest "$ROOT_DIR/seed/manifest.yaml" false >/dev/null 2>&1

# Modify user file (copy-once should preserve)
ORIG_HASH=$(sha256sum "$WORKSPACE_FULL_PATH/params.yaml" | cut -d' ' -f1)
echo "# user edit" >> "$WORKSPACE_FULL_PATH/params.yaml"
MOD_HASH=$(sha256sum "$WORKSPACE_FULL_PATH/params.yaml" | cut -d' ' -f1)
[ "$ORIG_HASH" != "$MOD_HASH" ] \
  && e2e_pass "user mod: params.yaml = $({ echo $MOD_HASH; } | head -c 8))" \
  || e2e_fail "user mod: no change"

# Second apply should preserve user edit (copy-once)
apply_manifest "$ROOT_DIR/seed/manifest.yaml" false >/dev/null 2>&1
FINAL_HASH=$(sha256sum "$WORKSPACE_FULL_PATH/params.yaml" | cut -d' ' -f1)
[ "$MOD_HASH" = "$FINAL_HASH" ] \
  && e2e_pass "copy-once: user params.yaml preserved after re-install" \
  || e2e_fail "copy-once: params.yaml overwritten on re-install"

rm -rf "$WS_DIR"

# === E2E-3 ===
echo ""
echo "=== E2E-3: Install + immediate update check ==="

WS_DIR=$(mktemp -d -t e2e-ws3-XXXXXX)
WORKSPACE_FULL_PATH="$WS_DIR/chktest"
export WORKSPACE_FULL_PATH
apply_manifest "$ROOT_DIR/seed/manifest.yaml" false >/dev/null 2>&1

# Create minimal workspace-link for update.sh
mkdir -p "$ROOT_DIR/workspaces" 2>/dev/null
CURRENT_LINK="$ROOT_DIR/workspaces/CURRENT_WORKSPACE"
# Don't overwrite existing link — check if already there
ORIG_LINK=""
[ -L "$CURRENT_LINK" ] && ORIG_LINK=$(readlink "$CURRENT_LINK")
ln -sf "$WORKSPACE_FULL_PATH" "$CURRENT_LINK" 2>/dev/null

# Run update check
output=$(bash "$UPDATE_SH" --check 2>&1) && rc=0 || rc=$?
echo "$output" | grep -q "update" 2>/dev/null \
  && e2e_pass "update: --check runs (rc=$rc)" \
  || e2e_fail "update: --check failed"

# Restore original link
[ -n "$ORIG_LINK" ] && ln -sf "$ORIG_LINK" "$CURRENT_LINK" 2>/dev/null || rm -f "$CURRENT_LINK" 2>/dev/null

rm -rf "$WS_DIR"

e2e_done
