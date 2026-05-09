#!/usr/bin/env bash
# seed-archgate-e2e.sh — workspace для ArchGate E2E: архитектурное решение
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
TARGET="${1:-$(mktemp -d "${ROOT_DIR}/.audit/test-seeds/archgate-e2e-XXXXXX")}"
mkdir -p "$TARGET/docs/adr"

# Architectural decision to evaluate
cat > "$TARGET/docs/adr/sample-decision.md" <<'EOF'
# Decision: Migrate from QEMU golden images to Docker containers for test isolation

## Context
Current test infrastructure uses QEMU/KVM golden images. Each test run requires:
1. Building a QCOW2 image (5-10 min)
2. Starting QEMU VM (30s)
3. Running tests inside VM via SSH

Proposal: replace with Podman containers using the existing Containerfile.

## Decision
Adopt Docker/Podman containers as the primary test isolation mechanism.
Keep QEMU golden images as a fallback for system-level tests only.

## Consequences
- Test startup time: 5-10 min → 30 seconds
- No SSH overhead
- No QEMU -daemonize PID issues
- Container images are smaller and faster to build
- Risk: uid mapping differences between host and container
EOF

# CLAUDE.md (simplified with ArchGate rules)
cat > "$TARGET/CLAUDE.md" <<'EOF'
# CLAUDE.md — test workspace

## ArchGate
Архитектурное решение → /archgate → 7 характеристик ЭМОГССБ:
Эволюционируемость, Масштабируемость, Обучаемость, Генеративность,
Скорость, Современность, Безопасность.

Шкала: ✅ Достаточно / ⚠️ Слабо / ❌ Блокер.
Veto правила: (1) ❌ в critical → STOP, (2) ≥2 ❌ → STOP.
3 modernity checks: SOTA.002, SOTA.001, SOTA.011.
ArchGate = gate (допуск), не ranker (выбор лучшего).
EOF

cd "$TARGET"
git init --quiet 2>/dev/null || true
git add -A >/dev/null 2>&1 || true
git commit -m "seed: ArchGate E2E test" --quiet 2>/dev/null || true

echo "$TARGET"
