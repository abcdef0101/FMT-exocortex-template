#!/usr/bin/env bash
# test-create-agents.sh — unit-тесты для create-agents.sh
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

CREATE="$ROOT_DIR/scripts/create-agents.sh"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Copy templates and model-tiers to temp dir (script resolves relative to ROOT_DIR)
export ROOT_DIR="$TMPDIR"
mkdir -p "$TMPDIR/seed/agents/templates"
cp -r "$(cd "$(dirname "$0")/../.." && pwd)/seed/agents/templates/"* "$TMPDIR/seed/agents/templates/"
mkdir -p "$TMPDIR/seed"
cp "$(cd "$(dirname "$0")/../.." && pwd)/seed/model-tiers.yaml" "$TMPDIR/seed/model-tiers.yaml"
# Also need ai-cli-wrapper.sh for resolve_model
mkdir -p "$TMPDIR/scripts"
cp "$(cd "$(dirname "$0")/../.." && pwd)/scripts/ai-cli-wrapper.sh" "$TMPDIR/scripts/ai-cli-wrapper.sh"
cp "$(cd "$(dirname "$0")/../.." && pwd)/scripts/create-agents.sh" "$TMPDIR/scripts/create-agents.sh"

echo "  --- create-agents.sh: Claude Code ---"

# Run the copy in TMPDIR so it generates files there
bash "$TMPDIR/scripts/create-agents.sh" --claude 2>/dev/null

[ -d "$TMPDIR/.claude/agents" ] \
  && _pass "creates .claude/agents/ directory" \
  || _fail "no .claude/agents/ directory"

for agent in verifier-code verifier-archgate verifier-capture verifier-chain verifier-adversarial; do
  [ -f "$TMPDIR/.claude/agents/${agent}.md" ] \
    && _pass "  ${agent}.md exists" \
    || _fail "  ${agent}.md MISSING"
done

# Check YAML frontmatter
FM_CHECK=$(head -1 "$TMPDIR/.claude/agents/verifier-code.md")
[ "$FM_CHECK" = "---" ] \
  && _pass "frontmatter starts with ---" \
  || _fail "frontmatter missing --- start"

# Check model field for claude (haiku/sonnet/opus aliases)
grep -q "model: sonnet" "$TMPDIR/.claude/agents/verifier-code.md" \
  && _pass "verifier-code model: sonnet" \
  || _fail "verifier-code model not sonnet"

grep -q "model: opus" "$TMPDIR/.claude/agents/verifier-archgate.md" \
  && _pass "verifier-archgate model: opus" \
  || _fail "verifier-archgate model not opus"

echo "  --- create-agents.sh: OpenCode ---"

bash "$TMPDIR/scripts/create-agents.sh" --opencode 2>/dev/null

[ -d "$TMPDIR/.opencode/agents" ] \
  && _pass "creates .opencode/agents/ directory" \
  || _fail "no .opencode/agents/ directory"

for agent in verifier-code verifier-archgate verifier-capture verifier-chain verifier-adversarial; do
  [ -f "$TMPDIR/.opencode/agents/${agent}.md" ] \
    && _pass "  ${agent}.md exists" \
    || _fail "  ${agent}.md MISSING"
done

# Check that opencode agent has full provider/model format
grep -q "model:" "$TMPDIR/.opencode/agents/verifier-code.md" \
  && _pass "opencode: model field present" \
  || _fail "opencode: model field missing"

# Check mode: subagent
grep -q "mode: subagent" "$TMPDIR/.opencode/agents/verifier-code.md" \
  && _pass "opencode: mode is subagent" \
  || _fail "opencode: mode not subagent"

echo "  --- syntax: all generated files have valid YAML frontmatter ---"
for agent_file in "$TMPDIR"/.claude/agents/*.md "$TMPDIR"/.opencode/agents/*.md; do
  name=$(basename "$agent_file")
  head -1 "$agent_file" | grep -q "^---$" \
    && _pass "  $name: --- start ok" \
    || _fail "  $name: frontmatter missing"
done

# ---------------------------------------------------------------------------
[ "$FAIL" -eq 0 ] && echo "  All tests passed" || echo "  $FAIL test(s) failed"
exit $FAIL
