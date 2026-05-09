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
  isSideSession,
  normalizeWpId,
  parseSessionTag,
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

// --- Side session detection ---
assert(isSideSession("WP-5 [audit]: CI gates") === true, "bracketed tag should be side session");
assert(isSideSession("WP-5 [review]: something") === true, "review tag should be side session");
assert(isSideSession("WP-5: CI gates") === false, "canonical title should not be side session");
assert(isSideSession("WP-5") === false, "bare WP id should not be side session");

const tag = parseSessionTag("WP-5 [audit]: CI gates");
assert(tag.isSide === true, "parseSessionTag should detect side");
assert(tag.tag === "audit", "parseSessionTag should extract tag");

const mainTag = parseSessionTag("WP-5: CI gates");
assert(mainTag.isSide === false, "parseSessionTag should detect main");
assert(mainTag.tag === null, "parseSessionTag should return null tag for main");

// --- Main preferred over side ---
const mixedRanked = rankSessionCandidates([
  { id: "side1", title: "WP-5 [audit]: CI review", time: { updated: 5 } },
  { id: "main1", title: "WP-5: CI gates", time: { updated: 3 } },
], "WP-5");
assert(mixedRanked[0].session.id === "main1", "main session should outrank side session");
assert(mixedRanked[0].score > 0, "main session should have positive score");
assert(mixedRanked[1].session.id === "side1", "side session should rank second");
assert(mixedRanked[1].score < mixedRanked[0].score, "side session should score below main");

const mixedDecision = chooseSessionCandidate(mixedRanked);
assert(mixedDecision.action === "select", "should auto-select main when side also exists");
assert(mixedDecision.candidate.session.id === "main1", "should select main, not side");

// --- Only side sessions: should create new main session ---
const onlySideRanked = rankSessionCandidates([
  { id: "s1", title: "WP-5 [audit]: review", time: { updated: 2 } },
], "WP-5");
const onlySideDecision = chooseSessionCandidate(onlySideRanked);
assert(onlySideDecision.action === "create", "should create new session when only side exists, not reuse side");

// --- Ambiguous main sessions ---
const ambiguousMain = chooseSessionCandidate([
  { session: { id: "m1", title: "WP-5: Alpha", time: { updated: 2 } }, score: 500 },
  { session: { id: "m2", title: "WP-5: Beta", time: { updated: 1 } }, score: 500 },
  { session: { id: "s1", title: "WP-5 [audit]: Gamma", time: { updated: 3 } }, score: -500 },
]);
assert(ambiguousMain.action === "ambiguous", "multiple main candidates should be ambiguous");
assert(ambiguousMain.candidates.length === 2, "ambiguity should only include main candidates, not side");
EOF

[ "$FAIL" -eq 0 ] && echo "  All tests passed" || echo "  $FAIL test(s) failed"
exit $FAIL
