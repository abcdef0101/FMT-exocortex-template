#!/usr/bin/env bash
# test-from-container.sh — run IWE test phases in a Podman container
# Analogous to test-from-golden.sh but uses podman exec instead of SSH.
#
# Usage:
#   bash scripts/container/test-from-container.sh                    # all 4 phases
#   bash scripts/container/test-from-container.sh --phase 1          # only phase 1
#   bash scripts/container/test-from-container.sh --version 0.25.1
#   bash scripts/container/test-from-container.sh --keep             # keep container after test
#   bash scripts/container/test-from-container.sh --verbose          # full output
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESULTS_DIR="$ROOT_DIR/scripts/container/results"

REPO_VERSION=""
RUN_PHASE="all"
KEEP_CONTAINER=false
VERBOSE=false
CONTAINER_NAME=""

while [ $# -gt 0 ]; do
  case "$1" in
    --version) REPO_VERSION="$2"; shift 2 ;;
    --version=*) REPO_VERSION="${1#*=}"; shift ;;
    --phase) RUN_PHASE="$2"; shift 2 ;;
    --phase=*) RUN_PHASE="${1#*=}"; shift ;;
    --keep) KEEP_CONTAINER=true; shift ;;
    --verbose|-v) VERBOSE=true; shift ;;
    --name) CONTAINER_NAME="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: test-from-container.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --version V   Version of container image (default: from MANIFEST.yaml)"
      echo "  --phase N     Run specific phase (1-4, 5a, 5, all, smoke)"
      echo "  --keep        Keep container after tests (for debugging)"
      echo "  --verbose     Show full output from test phases"
      echo "  --name NAME   Container name (default: auto-generated)"
      echo "  --help        This help"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [ -z "$REPO_VERSION" ]; then
  if [ -f "$ROOT_DIR/MANIFEST.yaml" ]; then
    REPO_VERSION=$(grep -m1 '^version:' "$ROOT_DIR/MANIFEST.yaml" | awk '{print $2}')
  fi
  [ -z "$REPO_VERSION" ] && { echo "ERROR: cannot detect version. Use --version." >&2; exit 1; }
fi

IMAGE_TAG="iwe-test:${REPO_VERSION}"
[ -z "$CONTAINER_NAME" ] && CONTAINER_NAME="iwe-test-$$"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT="$RESULTS_DIR/container-test-${TIMESTAMP}.txt"

mkdir -p "$RESULTS_DIR"

exec > >(tee "$REPORT") 2>&1

echo "========================================="
echo " IWE Container Test"
echo "========================================="
echo "  Version:   $REPO_VERSION"
echo "  Image:     $IMAGE_TAG"
echo "  Phase:     $RUN_PHASE"
echo "  Container: $CONTAINER_NAME"
echo "  Report:    $REPORT"
echo ""

# =========================================================================
# Pre-flight checks
# =========================================================================
command -v podman >/dev/null 2>&1 || { echo "ERROR: podman not found" >&2; exit 1; }

IMAGE_ID=$(podman images -q "$IMAGE_TAG" 2>/dev/null || true)
if [ -z "$IMAGE_ID" ]; then
  echo "ERROR: Image not found: $IMAGE_TAG" >&2
  echo "  Build it first: bash scripts/container/build-container.sh --version $REPO_VERSION" >&2
  exit 1
fi
echo "  Image ID: ${IMAGE_ID:0:12}"
echo ""

# =========================================================================
# Cleanup handler
# =========================================================================
cleanup() {
  if ! $KEEP_CONTAINER; then
    echo ""
    echo "--- Cleanup ---"
    podman rm -f "$CONTAINER_NAME" 2>/dev/null || true
    echo "  Container removed"
  fi
}
trap cleanup EXIT

# =========================================================================
# Step 1: Start container
# =========================================================================
echo "--- Step 1: Start Container ---"
TIME_START=$(date +%s)

podman run -d --name "$CONTAINER_NAME" "$IMAGE_TAG" >/dev/null 2>&1
TIME_CREATE=$(date +%s)
ELAPSED=$((TIME_CREATE - TIME_START))
echo "  ✓ Container started: $CONTAINER_NAME (${ELAPSED}s)"

# =========================================================================
# Step 2: Clone repo inside container
# =========================================================================
echo ""
echo "--- Step 2: Clone Repo ---"

REPO_URL="${IWE_REPO_URL:-https://github.com/abcdef0101/FMT-exocortex-template.git}"
REPO_BRANCH="${IWE_BRANCH:-0.25.1}"

podman exec "$CONTAINER_NAME" bash -c "rm -rf ~/IWE/FMT-exocortex-template && git clone --branch $REPO_BRANCH $REPO_URL ~/IWE/FMT-exocortex-template" 2>&1
CLONE_RC=$?

if [ "$CLONE_RC" -eq 0 ]; then
  echo "  ✓ Repo cloned ($REPO_BRANCH)"
else
  echo "  ✗ Repo clone FAILED (rc=$CLONE_RC)"
  exit 1
fi

# =========================================================================
# Step 3: Upload test artifacts
# =========================================================================
echo ""
echo "--- Step 3: Upload Test Artifacts ---"

# Upload test-phases.sh
podman cp "$ROOT_DIR/scripts/vm/test-phases.sh" "$CONTAINER_NAME:/home/iwe/test-phases.sh" 2>/dev/null || {
  echo "  ERROR: test-phases.sh upload failed"
  exit 1
}
echo "  ✓ test-phases.sh uploaded"

# Overlay local test scripts (ensures current fixes are tested)
podman cp "$ROOT_DIR/scripts/test/." "$CONTAINER_NAME:/home/iwe/IWE/FMT-exocortex-template/scripts/test/" 2>/dev/null || {
  echo "  WARN: test scripts upload failed (will use git clone version)"
}
echo "  ✓ test scripts uploaded"

# Upload secrets if available
SECRETS_DIR="$HOME/.iwe-test-vm/secrets"
HAS_SECRETS=false
if [ -d "$SECRETS_DIR" ] && [ -f "$SECRETS_DIR/.env" ]; then
  podman exec "$CONTAINER_NAME" bash -c "mkdir -p ~/secrets" 2>/dev/null
  podman cp "$SECRETS_DIR/.env" "$CONTAINER_NAME:/home/iwe/secrets/.env" 2>/dev/null || true
  podman exec "$CONTAINER_NAME" bash -c "chmod 600 ~/secrets/.env" 2>/dev/null
  HAS_SECRETS=true
  echo "  ✓ Secrets uploaded"
fi

# =========================================================================
# Step 4: Run tests
# =========================================================================
echo ""
echo "--- Step 4: Run Tests ---"

TOTAL_PASS=0
TOTAL_FAIL=0

run_phase() {
  local num="$1"
  local name="$2"
  local func="$3"

  echo ""
  echo "========================================="
  echo " Phase $num: $name"
  echo "========================================="
  echo ""

  SECRETS_PREAMBLE=""
  $HAS_SECRETS && SECRETS_PREAMBLE="[ -f ~/secrets/.env ] && set -a && source ~/secrets/.env && set +a;"

  PHASE_LOG="$RESULTS_DIR/phase-${num}-${TIMESTAMP}.log"
  PHASE_STDERR="$RESULTS_DIR/phase-${num}-stderr-${TIMESTAMP}.log"

  podman exec "$CONTAINER_NAME" \
    bash -c "$SECRETS_PREAMBLE cd ~/IWE/FMT-exocortex-template && source ~/test-phases.sh && $func" \
    >"$PHASE_LOG" 2>"$PHASE_STDERR" || true

  cat "$PHASE_LOG"

  if [ -s "$PHASE_STDERR" ]; then
    echo "  Phase $num stderr captured: $PHASE_STDERR ($(wc -l < "$PHASE_STDERR") lines)"
    if $VERBOSE; then
      echo "  --- Phase $num stderr ---"
      sed 's/^/  | /' "$PHASE_STDERR"
      echo "  --- end stderr ---"
    fi
  fi
}

case "$RUN_PHASE" in
  1)       run_phase 1 "Clean Install" "phase1_setup" ;;
  2)       run_phase 2 "Update" "phase2_update" ;;
  3|smoke) run_phase 3 "AI Smoke" "phase3_ai_smoke" ;;
  4)       run_phase 4 "CI + Migrations" "phase4_ci" ;;
  5a)      run_phase "5a" "Strategy Session (structural)" "phase5a_strategy_session" ;;
  5|5b|e2e) run_phase "5b" "Strategy Session (headless E2E)" "phase5b_strategy_session" ;;
  all)
    run_phase 1 "Clean Install" "phase1_setup"
    run_phase 2 "Update" "phase2_update"
    run_phase 3 "AI Smoke" "phase3_ai_smoke"
    run_phase 4 "CI + Migrations" "phase4_ci"
    run_phase "5a" "Strategy Session (structural)" "phase5a_strategy_session"
    ;;
  *) echo "ERROR: invalid phase: $RUN_PHASE"; exit 1 ;;
esac

TOTAL_PASS=$(grep -cE '\[OK\]|\[OK\*\]' "$REPORT" 2>/dev/null | tr -d '\n' || echo "0")
TOTAL_FAIL=$(grep -c '\[FAIL\]' "$REPORT" 2>/dev/null | tr -d '\n' || echo "0")

# Collect phase metrics from container
METRICS_FILE="$RESULTS_DIR/metrics-${TIMESTAMP}.txt"
podman cp "$CONTAINER_NAME:/tmp/iwe-phase-metrics.txt" "$METRICS_FILE" 2>/dev/null || true

# =========================================================================
# Step 5: Report
# =========================================================================
echo ""
echo "========================================="
echo " IWE Container Test Report"
echo "========================================="
echo ""
echo "  Version:    $REPO_VERSION"
echo "  Phase:      $RUN_PHASE"
echo "  Start time: ${ELAPSED}s"
echo "  Passed:     $TOTAL_PASS"
echo "  Failed:     $TOTAL_FAIL"
echo "  Report:     $REPORT"
echo ""

if $KEEP_CONTAINER; then
  echo "  Container KEPT for debugging."
  echo "  Exec:  podman exec -it $CONTAINER_NAME bash"
  echo "  Stop:  podman rm -f $CONTAINER_NAME"
  trap - EXIT
fi

echo "========================================="

exit $(( TOTAL_FAIL ))
