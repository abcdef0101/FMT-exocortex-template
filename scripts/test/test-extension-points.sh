#!/usr/bin/env bash
# test-extension-points.sh — проверка согласованности extension-points.yaml с params.yaml
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

EP_FILE="$ROOT_DIR/extension-points.yaml"
PARAMS_FILE="$ROOT_DIR/seed/params.yaml"

[ -f "$EP_FILE" ]  || { _fail "extension-points.yaml not found"; exit 1; }
[ -f "$PARAMS_FILE" ] || { _fail "seed/params.yaml not found"; exit 1; }

# Extract toggle values from extension-points.yaml (lines like "    toggle: day_open_before_enabled")
toggles=$(grep 'toggle:' "$EP_FILE" | sed 's/.*toggle: *//')
param_keys=$(grep -oP '^[a-z_]+:' "$PARAMS_FILE" | sed 's/:$//' | grep -v '^$' || true)

# -------------------------------------------------------------------
echo "  --- toggle-to-params consistency ---"

missing_toggles=0
while IFS= read -r toggle; do
  [ -z "$toggle" ] && continue
  if echo "$param_keys" | grep -qx "$toggle"; then
    : # match
  else
    _fail "toggle '$toggle' not found in params.yaml"
    missing_toggles=$((missing_toggles + 1))
  fi
done <<< "$toggles"

[ "$missing_toggles" -eq 0 ] \
  && _pass "all toggles exist in params.yaml ($(echo "$toggles" | wc -l) checked)" \
  || true

# -------------------------------------------------------------------
echo "  --- file naming convention ---"

# All protocol hook files should match extensions/*.md pattern
protocol_hooks=$(grep 'file: extensions/' "$EP_FILE" | sed 's/.*file: *//')
hook_violations=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if [[ "$f" =~ ^extensions/[a-z._-]+\.md$ ]]; then
    : # valid
  else
    _fail "invalid protocol hook filename: $f"
    hook_violations=$((hook_violations + 1))
  fi
done <<< "$protocol_hooks"

[ "$hook_violations" -eq 0 ] \
  && _pass "protocol hook filenames valid ($(echo "$protocol_hooks" | wc -l) checked)" \
  || true

# -------------------------------------------------------------------
echo "  --- mode enum validation ---"

modes=$(grep 'mode:' "$EP_FILE" | sed 's/.*mode: *//')
valid_modes=("before" "after" "blocking")
mode_violations=0
while IFS= read -r mode; do
  [ -z "$mode" ] && continue
  found=0
  for vm in "${valid_modes[@]}"; do [ "$mode" = "$vm" ] && found=1; done
  [ "$found" -eq 0 ] && { _fail "invalid mode: '$mode'"; mode_violations=$((mode_violations + 1)); }
done <<< "$modes"

[ "$mode_violations" -eq 0 ] \
  && _pass "all modes valid ($(echo "$modes" | wc -l) checked)" \
  || true

# -------------------------------------------------------------------
echo "  --- protocol enum validation ---"

protocols=$(grep 'protocol:' "$EP_FILE" | sed 's/.*protocol: *//' | grep -v '^yaml$' | grep -v '^markdown$' | grep -v '^json$' | grep -v '^bash$' || true)
if [ -z "$protocols" ]; then
  _pass "all protocols valid"
else
  _fail "invalid protocols found: $protocols"
fi

# -------------------------------------------------------------------
echo "  --- id uniqueness ---"

ids=$(grep '^  - id:' "$EP_FILE" | sed 's/.*id: *//')
dup_count=$(echo "$ids" | sort | uniq -d | wc -l)
[ "$dup_count" -eq 0 ] \
  && _pass "all ids unique ($(echo "$ids" | wc -l) entries, 0 duplicates)" \
  || _fail "$dup_count duplicate ids found"

# -------------------------------------------------------------------
echo "  --- since versions ---"

since_versions=$(grep 'since:' "$EP_FILE" | sed 's/.*since: *//')
version_violations=0
current_version="0.25.1"

version_le() {
  # Return 0 if $1 <= $2 (semver comparison)
  local IFS=.
  local i a1 a2 b1 b2
  read -ra a <<< "$1"
  read -ra b <<< "$2"
  a1=${a[0]}; a2=${a[1]}; b1=${b[0]}; b2=${b[1]}
  # strip leading zeros
  a1=$((10#${a1})); a2=$((10#${a2}))
  b1=$((10#${b1})); b2=$((10#${b2}))
  [ "$a1" -lt "$b1" ] && return 0
  [ "$a1" -gt "$b1" ] && return 1
  [ "$a2" -le "$b2" ] && return 0
  return 1
}

while IFS= read -r sv; do
  [ -z "$sv" ] && continue
  if version_le "$sv" "$current_version"; then
    :
  else
    _fail "since version '$sv' > current '$current_version'"
    version_violations=$((version_violations + 1))
  fi
done <<< "$since_versions"

[ "$version_violations" -eq 0 ] \
  && _pass "all since versions <= $current_version ($(echo "$since_versions" | wc -l) checked)" \
  || true

# -------------------------------------------------------------------
echo "  --- never_touch markers ---"

nt_count=$(grep -c 'never_touch: true' "$EP_FILE" || true)
[ "$nt_count" -ge 5 ] \
  && _pass "never_touch markers: $nt_count config points protected" \
  || _fail "never_touch markers: expected >=5, got $nt_count"

# -------------------------------------------------------------------
echo "  --- source file existence ---"

# Only check points that have a 'source:' field (template files that must exist)
source_entries=$(grep 'source:' "$EP_FILE" | sed 's/.*source: *//')
source_missing=0
while IFS= read -r s; do
  [ -z "$s" ] && continue
  # Expand $WORKSPACE_FULL_PATH — but source paths in template are always relative to seed/
  # The source: field points to seed/ files, e.g. "seed/CLAUDE.md"
  if [ -e "$ROOT_DIR/$s" ]; then
    : # exists in template
  else
    _fail "source not found: $s (from $EP_FILE)"
    source_missing=$((source_missing + 1))
  fi
done <<< "$source_entries"

[ "$source_missing" -eq 0 ] \
  && _pass "all source files exist ($(echo "$source_entries" | wc -l) checked)" \
  || true

# -------------------------------------------------------------------
[ "$FAIL" -eq 0 ] && echo "  All tests passed" || echo "  $FAIL test(s) failed"
exit $FAIL
