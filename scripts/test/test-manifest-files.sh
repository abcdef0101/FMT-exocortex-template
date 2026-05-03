#!/usr/bin/env bash
# test-manifest-files.sh — валидация всех MANIFEST.yaml файлов
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

# Find all MANIFEST.yaml (exclude temp, workspaces, git)
mapfile -t manifests < <(find "$ROOT_DIR" -name "MANIFEST.yaml" \
  -not -path "*/.git/*" \
  -not -path "*/workspaces/*" \
  -not -path "*/DS-strategy/*" \
  -not -path "*/DS-agent-workspace/*" \
  | sort)

[ "${#manifests[@]}" -gt 0 ] || { _fail "no MANIFEST.yaml files found"; exit 1; }

echo "  --- found ${#manifests[@]} MANIFEST.yaml files ---"

# -------------------------------------------------------------------
echo "  --- required fields ---"

valid_semver() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]
}

total=${#manifests[@]}
good_component=0 good_version=0 good_semver=0 good_contract=0

for mf in "${manifests[@]}"; do
  rel="${mf#$ROOT_DIR/}"

  if grep -q '^component:' "$mf"; then
    good_component=$((good_component + 1))
  else
    _fail "$rel: missing component"
  fi

  if grep -q '^version:' "$mf"; then
    good_version=$((good_version + 1))
    ver=$(grep '^version:' "$mf" | head -1 | awk '{print $2}')
    if valid_semver "$ver"; then
      good_semver=$((good_semver + 1))
    else
      _fail "$rel: invalid semver: $ver"
    fi
  else
    _fail "$rel: missing version"
  fi

  if grep -q '^api_contract:' "$mf"; then
    good_contract=$((good_contract + 1))
  else
    _fail "$rel: missing api_contract"
  fi
done

[ "$good_component" -eq "$total" ] \
  && _pass "component: $good_component/$total" \
  || _fail "component: $good_component/$total"

[ "$good_version" -eq "$total" ] \
  && _pass "version: $good_version/$total" \
  || _fail "version: $good_version/$total"

[ "$good_semver" -eq "$total" ] \
  && _pass "semver valid: $good_semver/$total" \
  || _fail "semver valid: $good_semver/$total"

[ "$good_contract" -eq "$total" ] \
  && _pass "api_contract: $good_contract/$total" \
  || _fail "api_contract: $good_contract/$total"

# -------------------------------------------------------------------
echo "  --- inputs/outputs lists ---"

inputs_ok=0 outputs_ok=0
for mf in "${manifests[@]}"; do
  rel="${mf#$ROOT_DIR/}"
  # api_contract should have inputs: and outputs: as YAML lists
  # Simple check: both keys present somewhere after api_contract
  if grep -A 20 '^api_contract:' "$mf" | grep -q 'inputs:'; then
    inputs_ok=$((inputs_ok + 1))
  fi
  if grep -A 20 '^api_contract:' "$mf" | grep -q 'outputs:'; then
    outputs_ok=$((outputs_ok + 1))
  fi
done

[ "$inputs_ok" -eq "$total" ] \
  && _pass "inputs defined: $inputs_ok/$total" \
  || { [ "$inputs_ok" -lt "$total" ] && _fail "inputs defined: $inputs_ok/$total (some missing)"; }

[ "$outputs_ok" -ge "$((total - 1))" ] \
  && _pass "outputs defined: $outputs_ok/$total" \
  || _fail "outputs defined: $outputs_ok/$total"

# -------------------------------------------------------------------
echo "  --- YAML validity ---"

yaml_ok=0
yaml_fail=0
if command -v ruby &>/dev/null; then
  for mf in "${manifests[@]}"; do
    if ruby -ryaml -e "YAML.load_file('$mf')" 2>/dev/null; then
      yaml_ok=$((yaml_ok + 1))
    else
      _fail "invalid YAML: ${mf#$ROOT_DIR/}"
      yaml_fail=$((yaml_fail + 1))
    fi
  done
  [ "$yaml_fail" -eq 0 ] \
    && _pass "YAML valid: $yaml_ok/$total" \
    || _fail "YAML valid: $yaml_ok/$total, $yaml_fail errors"
else
  echo "  - skipped YAML validation (no ruby)"
fi

# -------------------------------------------------------------------
echo "  --- version consistency ---"

# Root CLAUDE.md version vs CHANGELOG
if [ -f "$ROOT_DIR/MANIFEST.yaml" ]; then
  root_ver=$(grep '^version:' "$ROOT_DIR/MANIFEST.yaml" | awk '{print $2}')
  changelog_head=$(grep -m1 '^## \[' "$ROOT_DIR/CHANGELOG.md" | sed 's/.*\[//;s/\].*//' || true)
  if [ -n "$changelog_head" ]; then
    [ "$root_ver" = "$changelog_head" ] \
      && _pass "root version ($root_ver) matches CHANGELOG ($changelog_head)" \
      || _fail "root version ($root_ver) != CHANGELOG ($changelog_head)"
  fi
fi

# -------------------------------------------------------------------
[ "$FAIL" -eq 0 ] && echo "  All tests passed" || echo "  $FAIL test(s) failed"
exit $FAIL
