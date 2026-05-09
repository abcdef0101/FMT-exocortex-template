#!/usr/bin/env bash
# test-opencode-wp-session.sh — unit tests for OpenCode WP session helper logic
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FAIL=0

_pass() { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

LIB="$ROOT_DIR/.opencode/plugins/wp-session-lib.js"

echo "  --- library exists ---"
[ -f "$LIB" ] \
  && _pass "wp-session-lib.js exists" \
  || _fail "wp-session-lib.js missing"

echo "  --- node-based assertions ---"
node --input-type=module <<'EOF' || FAIL=$((FAIL + 1))
import {
  canonicalWpSessionTitle,
  chooseSessionCandidate,
  normalizeWpId,
  rankSessionCandidates,
  stripWpPrefix,
} from "./.opencode/plugins/wp-session-lib.js";

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

assert(normalizeWpId("5") === "WP-5", "number normalization failed");
assert(normalizeWpId("WP-5") === "WP-5", "WP normalization failed");
assert(normalizeWpId("РП5") === "WP-5", "RP normalization failed");
assert(normalizeWpId("bad") === null, "invalid normalization should return null");

assert(stripWpPrefix("WP-5 CI gates", "WP-5") === "CI gates", "WP prefix stripping failed");
assert(stripWpPrefix("РП5: CI gates", "WP-5") === "CI gates", "RP prefix stripping failed");
assert(canonicalWpSessionTitle("WP-5", "WP-5 CI gates") === "WP-5: CI gates", "canonical title failed");

const sessions = [
  { id: "a", title: "notes about WP-5", time: { updated: 1 } },
  { id: "b", title: "WP-5: CI gates", time: { updated: 2 } },
  { id: "c", title: "РП5", time: { updated: 3 } },
];

const ranked = rankSessionCandidates(sessions, "WP-5");
assert(ranked[0].session.id === "b", "ranking should prefer canonical prefix");

const decision = chooseSessionCandidate(ranked);
assert(decision.action === "select", "canonical match should be auto-selected");
assert(decision.candidate.session.id === "b", "selected session mismatch");

const ambiguous = chooseSessionCandidate([
  { session: { id: "x", title: "WP-5: A", time: { updated: 2 } }, score: 500 },
  { session: { id: "y", title: "WP-5: B", time: { updated: 1 } }, score: 500 },
]);
assert(ambiguous.action === "ambiguous", "equal strong scores should be ambiguous");

const create = chooseSessionCandidate([
  { session: { id: "x", title: "notes about WP-5", time: { updated: 2 } }, score: 200 },
]);
assert(create.action === "create", "weak fuzzy match should not auto-select");
EOF

[ "$FAIL" -eq 0 ] && echo "  All tests passed" || echo "  $FAIL test(s) failed"
exit $FAIL
