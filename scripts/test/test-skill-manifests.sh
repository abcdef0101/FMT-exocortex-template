#!/usr/bin/env bash
# test-skill-manifests.sh — проверка скиллов (§13, workflow-full.md)
# Каждый скилл в .claude/skills/ должен иметь SKILL.md + MANIFEST.yaml
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
SKILLS_DIR="$ROOT_DIR/.claude/skills"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- skill files ---"

skill_count=0
has_skill_md=0
has_manifest=0

for skill_dir in "$SKILLS_DIR"/*/; do
  [ ! -d "$skill_dir" ] && continue
  name=$(basename "$skill_dir")
  skill_count=$((skill_count + 1))

  if [ -f "$skill_dir/SKILL.md" ]; then
    has_skill_md=$((has_skill_md + 1))
  else
    _fail "$name: SKILL.md missing"
  fi

  if [ -f "$skill_dir/MANIFEST.yaml" ]; then
    has_manifest=$((has_manifest + 1))
  else
    _fail "$name: MANIFEST.yaml missing"
  fi
done

echo "  skills: $skill_count total, $has_skill_md with SKILL.md, $has_manifest with MANIFEST.yaml"

echo "  --- skill names match directory ---"

for skill_dir in "$SKILLS_DIR"/*/; do
  [ ! -d "$skill_dir" ] && continue
  name=$(basename "$skill_dir")
  mf="$skill_dir/MANIFEST.yaml"
  [ ! -f "$mf" ] && continue

  comp=$(grep '^component:' "$mf" | awk '{print $2}' || true)
  expected="skill/$name"
  if [ "$comp" = "$expected" ]; then
    _pass "$name: component=$expected"
  else
    _fail "$name: component=$comp (expected $expected)"
  fi
done

echo "  --- skill SKILL.md non-empty ---"

for skill_dir in "$SKILLS_DIR"/*/; do
  [ ! -d "$skill_dir" ] && continue
  name=$(basename "$skill_dir")
  sm="$skill_dir/SKILL.md"
  [ ! -f "$sm" ] && continue
  [ -s "$sm" ] \
    && _pass "$name: SKILL.md non-empty ($(wc -l < "$sm") lines)" \
    || _fail "$name: SKILL.md is empty"
done

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL