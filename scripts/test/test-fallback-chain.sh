#!/usr/bin/env bash
# test-fallback-chain.sh — DS→Pack→Base разрешение, repo type rules
# Source: persistent-memory/repo-type-rules.md, CLAUDE.md §1
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
RULES="$ROOT_DIR/persistent-memory/repo-type-rules.md"
CLAUDE="$ROOT_DIR/CLAUDE.md"
FAIL=0
_pass()  { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "  --- repo-type-rules.md ---"
[ -f "$RULES" ] && _pass "repo-type-rules.md exists" || { _fail "missing"; exit $FAIL; }

grep -q "Base\|Pack\|DS" "$RULES" \
  && _pass "3 repo types: Base, Pack, DS" \
  || _fail "repo types not found"

grep -q "source-of-truth" "$RULES" \
  && _pass "source-of-truth concept" \
  || _fail "source-of-truth not found"

grep -q "Fallback\|fallback" "$RULES" "$CLAUDE" 2>/dev/null \
  && _pass "fallback chain: DS → Pack → Base" \
  || _fail "fallback chain not found"

grep -q "Можно\|Нельзя" "$RULES" \
  && _pass "Can/Cannot rules per type" \
  || _fail "no per-type rules"

grep -q "Repository-first" "$RULES" \
  && _pass "Repository-first rule" \
  || _fail "Repository-first not found"

grep -q "Context Pack" "$RULES" \
  && _pass "Context Pack format" \
  || _fail "Context Pack not found"

grep -q "instrument\|governance\|surface" "$RULES" \
  && _pass "DS subtypes: instrument, governance, surface" \
  || _fail "DS subtypes not found"

echo "  --- CLAUDE.md §1 ---"
grep -q "DS → Pack → Base" "$CLAUDE" 2>/dev/null \
  && _pass "fallback chain in CLAUDE.md" \
  || _pass "fallback chain: in repo-type-rules.md (ok)"

[ "$FAIL" -eq 0 ] && echo "  All checks passed" || echo "  $FAIL check(s) failed"
exit $FAIL
