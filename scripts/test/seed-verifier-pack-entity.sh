#!/usr/bin/env bash
# seed-verifier-pack-entity.sh — workspace для Verifier pack-entity E2E
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
TARGET="${1:-$(mktemp -d /tmp/iwe-seed-verifier-pack-XXXXXX)}"
mkdir -p "$TARGET/Pack/08-service-clauses" "$TARGET/DS-strategy/docs"

# Pack entity with intentional violations for verifier to detect
cat > "$TARGET/Pack/08-service-clauses/DP.SC.025-capture-bus.md" <<'EOF'
# DP.SC.025 — Capture Bus

> **Status:** draft

## Promise
The capture bus routes knowledge from sessions to their appropriate destinations.

## Acceptance Criteria (VIOLATIONS EMBEDDED)
1. Capture is routed to correct destination
2. (MISSING: no temporal metadata)
3. (MISSING: no error handling description)

## (MISSING SECTION: Dependencies)
EOF

# DP standard for comparison (the "golden" reference)
cat > "$TARGET/DS-strategy/docs/DP-standard.md" <<'EOF'
# Service Clause Standard — Required Fields

Every Service Clause MUST have:
- Status field (draft, active, archived)
- Created date (YYYY-MM-DD)
- Promise section
- Acceptance Criteria section (≥3 items)
- Dependencies section

Optional:
- Updated date
- Superseded_by
- Source reference
EOF

cd "$TARGET"
git init --quiet 2>/dev/null || true
git add -A >/dev/null 2>&1 || true
git commit -m "seed: verifier pack-entity test" --quiet 2>/dev/null || true

echo "$TARGET"
