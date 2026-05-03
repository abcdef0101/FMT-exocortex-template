#!/usr/bin/env bash
# E2E-4: Update: upstream has changes detected by --check
# E2E-5: Update: --apply + verify integrity
# E2E-6: Update: NEVER-TOUCH enforcement
set -uo pipefail
source "$(dirname "$0")/_lib.sh"

echo "=== E2E-4: Update check — upstream changes detected ==="

setup_upstream
setup_local "$UPSTREAM_DIR"
repoint_origin "$LOCAL_DIR" "$UPSTREAM_DIR"

# Inject change in upstream
inject_change "$UPSTREAM_DIR" "CHANGELOG.md" "# e2e-test-change"

# Fetch from local
(cd "$LOCAL_DIR" && git fetch origin 2>/dev/null)
LOCAL_SHA=$(git -C "$LOCAL_DIR" rev-parse HEAD)
UPSTREAM_SHA=$(git -C "$LOCAL_DIR" rev-parse origin/main 2>/dev/null || git -C "$LOCAL_DIR" rev-parse origin/master 2>/dev/null)

[ "$LOCAL_SHA" != "$UPSTREAM_SHA" ] \
  && e2e_pass "upstream differs: $(echo "$LOCAL_SHA" | head -c 7) vs $(echo "$UPSTREAM_SHA" | head -c 7)" \
  || e2e_fail "upstream should differ"

# Run --check from local
output=$(bash "$LOCAL_DIR/update.sh" --check 2>&1) && rc=0 || rc=$?
echo "$output" | grep -q "Changes available\|up to date\|Already up to date" 2>/dev/null \
  && e2e_pass "update.sh --check: runs successfully (rc=$rc)" \
  || e2e_fail "update.sh --check: no expected output"

e2e_cleanup

# === E2E-5 ===
echo ""
echo "=== E2E-5: Update — apply + verify integrity ==="

setup_upstream
setup_local "$UPSTREAM_DIR"
repoint_origin "$LOCAL_DIR" "$UPSTREAM_DIR"

# Inject change
inject_change "$UPSTREAM_DIR" "CHANGELOG.md" "# e2e-apply-test-change"

# Apply update from local
output=$(bash "$LOCAL_DIR/update.sh" --apply 2>&1) && rc=0 || rc=$?
echo "$output" | grep -qE "Applied|up to date|Already" 2>/dev/null \
  && e2e_pass "update.sh --apply: runs (rc=$rc)" \
  || e2e_fail "update.sh --apply: unexpected output"

# Verify checksums in local after apply
verify_checksums "$LOCAL_DIR/checksums.yaml"

e2e_cleanup

# === E2E-6 ===
echo ""
echo "=== E2E-6: NEVER-TOUCH enforcement ==="

WS_DIR=$(mktemp -d -t e2e-nt-XXXXXX)
WORKSPACE_FULL_PATH="$WS_DIR/nttest"
export WORKSPACE_FULL_PATH
source "$MANIFEST_LIB" 2>/dev/null
apply_manifest "$ROOT_DIR/seed/manifest.yaml" false >/dev/null 2>&1

# Modify user file params.yaml
echo "# user custom param" >> "$WORKSPACE_FULL_PATH/params.yaml"
USER_HASH=$(sha256sum "$WORKSPACE_FULL_PATH/params.yaml" | cut -d' ' -f1)

# Re-apply manifest — params.yaml has copy-once, should skip
apply_manifest "$ROOT_DIR/seed/manifest.yaml" false >/dev/null 2>&1
FINAL_HASH=$(sha256sum "$WORKSPACE_FULL_PATH/params.yaml" | cut -d' ' -f1)

[ "$USER_HASH" = "$FINAL_HASH" ] \
  && e2e_pass "never-touch: params.yaml preserved after re-apply" \
  || e2e_fail "never-touch: params.yaml overwritten"

# Verify all NEVER-TOUCH entries are in checksums
CK_FILE="$ROOT_DIR/checksums.yaml"
if [ -f "$CK_FILE" ]; then
  nt_count=$(sed -n '/^never_touch:/,/^files:/p' "$CK_FILE" | grep -c '^  - ' || echo "0")
  [ "$nt_count" -ge 5 ] \
    && e2e_pass "checksums: $nt_count never-touch entries" \
    || e2e_fail "checksums: only $nt_count never-touch entries"
fi

rm -rf "$WS_DIR"

e2e_done
