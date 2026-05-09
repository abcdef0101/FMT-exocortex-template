#!/usr/bin/env bash
# seed-skill-invocation-e2e.sh — workspace для Skill Invocation E2E (/verify)
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
TARGET="${1:-$(mktemp -d "${ROOT_DIR}/.audit/test-seeds/skill-invoke-e2e-XXXXXX")}"
mkdir -p "$TARGET/Pack/08-service-clauses" "$TARGET/DS-strategy/docs"

# Pack file with intentional violations
cat > "$TARGET/Pack/08-service-clauses/DP.SC.025-capture-bus.md" <<'EOF'
# DP.SC.025 — Capture Bus

> **Status:** draft
> **Created:** 2026-04-01

## Promise
Routes knowledge from sessions to appropriate destinations.

## Acceptance Criteria
1. Capture is routed to correct destination
2. (MISSING: no more items — need ≥3)

## (MISSING SECTION: Dependencies)
EOF

# DP standard for comparison
cat > "$TARGET/DS-strategy/docs/DP-standard.md" <<'EOF'
# Service Clause Standard
Every Service Clause MUST have:
- Status field (draft/active/archived)
- Created date (YYYY-MM-DD)
- Promise section
- Acceptance Criteria (≥3 items)
- Dependencies section
EOF

# CLAUDE.md with skill reference
cat > "$TARGET/CLAUDE.md" <<'EOF'
# CLAUDE.md — test workspace
Use /verify to validate Pack entities against DP standards.
The verifier checks: status, created date, promise, acceptance criteria (≥3), dependencies.
Output: structured findings with severity (P0/P1/P2), evidence (path:line), description.
EOF

cd "$TARGET"
git init --quiet 2>/dev/null || true
git add -A >/dev/null 2>&1 || true
git commit -m "seed: Skill Invocation E2E test" --quiet 2>/dev/null || true

echo "$TARGET"
