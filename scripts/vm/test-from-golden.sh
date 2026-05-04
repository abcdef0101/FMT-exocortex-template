#!/usr/bin/env bash
# test-from-golden.sh — ephemeral VM + прогон тестов из золотого образа IWE
#
# Создаёт copy-on-write клон, запускает VM, прогоняет тесты, удаляет VM.
# Время: <30 сек на создание окружения (вместо 15 мин текущего цикла).
#
# Использование:
#   bash scripts/vm/test-from-golden.sh                          # все 4 фазы
#   bash scripts/vm/test-from-golden.sh --phase 1                # только фаза 1
#   bash scripts/vm/test-from-golden.sh --version 0.25.1         # конкретная версия
#   bash scripts/vm/test-from-golden.sh --keep                   # не удалять VM после теста
#   bash scripts/vm/test-from-golden.sh --port 2223              # фиксированный порт
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESULTS_DIR="$ROOT_DIR/scripts/vm/results"

REPO_VERSION=""
RUN_PHASE="all"
SSH_KEY="$HOME/.ssh/id_ed25519_iwe_test"
KEEP_VM=false
SSH_PORT=""

# === Parse args ===
while [ $# -gt 0 ]; do
  case "$1" in
    --version) REPO_VERSION="$2"; shift 2 ;;
    --version=*) REPO_VERSION="${1#*=}"; shift ;;
    --phase) RUN_PHASE="$2"; shift 2 ;;
    --phase=*) RUN_PHASE="${1#*=}"; shift ;;
    --keep) KEEP_VM=true; shift ;;
    --port) SSH_PORT="$2"; shift 2 ;;
    --port=*) SSH_PORT="${1#*=}"; shift ;;
    --help|-h)
      echo "Usage: test-from-golden.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --version V   Version of golden image (default: from MANIFEST.yaml)"
      echo "  --phase N     Run specific phase (1-4, or 'all', 'smoke')"
      echo "  --keep        Keep VM running after tests (for debugging)"
      echo "  --port N      SSH port forward (default: auto-find from 2222)"
      echo "  --help        This help"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# === Version detection ===
if [ -z "$REPO_VERSION" ]; then
  if [ -f "$ROOT_DIR/MANIFEST.yaml" ]; then
    REPO_VERSION=$(grep -m1 '^version:' "$ROOT_DIR/MANIFEST.yaml" | awk '{print $2}')
  fi
  [ -z "$REPO_VERSION" ] && { echo "ERROR: cannot detect version. Use --version." >&2; exit 1; }
fi

# === Derived paths ===
CACHE_DIR="$HOME/.cache/iwe-golden"
GOLDEN_IMAGE="$CACHE_DIR/iwe-golden-${REPO_VERSION}.qcow2"
TEST_IMAGE="/tmp/iwe-ephemeral-$$.qcow2"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT="$RESULTS_DIR/golden-test-${TIMESTAMP}.txt"

mkdir -p "$RESULTS_DIR"

# Redirect all output to both stdout and report file
exec > >(tee "$REPORT") 2>&1

echo "========================================="
echo " IWE Golden Image Test"
echo "========================================="
echo "  Version: $REPO_VERSION"
echo "  Phase:   $RUN_PHASE"
echo "  Report:  $REPORT"
echo ""

# =========================================================================
# Pre-flight checks
# =========================================================================
if ! command -v qemu-img >/dev/null 2>&1; then
  echo "ERROR: qemu-img not found. Install: sudo apt install qemu-kvm" >&2
  exit 1
fi

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
  echo "ERROR: qemu-system-x86_64 not found." >&2
  exit 1
fi

if [ ! -f "$GOLDEN_IMAGE" ]; then
  echo "ERROR: Golden image not found: $GOLDEN_IMAGE" >&2
  echo "  Build it first: bash scripts/vm/build-golden.sh --version $REPO_VERSION" >&2
  exit 1
fi

if [ ! -f "$GOLDEN_IMAGE.sha256" ]; then
  echo "WARN: No checksum file found, skipping verification"
else
  EXPECTED=$(cut -d' ' -f1 "$GOLDEN_IMAGE.sha256")
  ACTUAL=$(sha256sum "$GOLDEN_IMAGE" | cut -d' ' -f1)
  if [ "$EXPECTED" != "$ACTUAL" ]; then
    echo "ERROR: Golden image checksum MISMATCH. Rebuild with --force." >&2
    exit 1
  fi
  echo "  Checksum: OK (${ACTUAL:0:16}...)"
fi

if [ ! -f "$SSH_KEY" ]; then
  echo "  SSH key not found, generating..."
  ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "iwe-test" -q
  echo "  ✓ Generated: $SSH_KEY"
fi

echo "  SSH key: $(ssh-keygen -l -f "$SSH_KEY" 2>/dev/null | awk '{print $1, $3}')"
echo ""

# =========================================================================
# Cleanup handler
# =========================================================================
VM_PID=""
cleanup() {
  echo ""
  echo "--- Cleanup ---"
  if [ -n "$VM_PID" ] && kill -0 "$VM_PID" 2>/dev/null; then
    echo "  Stopping QEMU (PID $VM_PID)..."
    kill "$VM_PID" 2>/dev/null || true
    sleep 2
    kill -9 "$VM_PID" 2>/dev/null || true
  fi
  if [ -f "$TEST_IMAGE" ]; then
    rm -f "$TEST_IMAGE"
    echo "  Removed: $TEST_IMAGE"
  fi
}
trap cleanup EXIT

# =========================================================================
# Step 1: Create ephemeral VM (copy-on-write, seconds)
# =========================================================================
echo "--- Step 1: Create Ephemeral VM ---"
TIME_START=$(date +%s)

qemu-img create -f qcow2 -b "$GOLDEN_IMAGE" -F qcow2 "$TEST_IMAGE" 20G >/dev/null 2>&1
TIME_CREATE=$(date +%s)
ELAPSED=$((TIME_CREATE - TIME_START))
echo "  ✓ Created ephemeral image (${ELAPSED}s)"
echo ""

# =========================================================================
# Step 2: Find free port and boot VM
# =========================================================================
echo "--- Step 2: Boot VM ---"

if [ -z "$SSH_PORT" ]; then
  SSH_PORT=2222
  while ss -tlnp 2>/dev/null | grep -q ":$SSH_PORT "; do
    SSH_PORT=$((SSH_PORT + 1))
    [ "$SSH_PORT" -gt 2232 ] && { echo "ERROR: no free ports 2222-2232" >&2; exit 1; }
  done
fi

qemu-system-x86_64 -enable-kvm -m 4096 -smp 2 \
  -drive file="$TEST_IMAGE",if=virtio \
  -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22 \
  -device virtio-net,netdev=net0 \
  -display none -daemonize &

VM_PID=$!
echo "  Port: $SSH_PORT (PID $VM_PID)"

# =========================================================================
# Step 3: Wait for SSH
# =========================================================================
echo ""
echo "--- Step 3: Wait for SSH ---"

SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3 -o ServerAliveInterval=5 -p $SSH_PORT"
SCP_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P $SSH_PORT -q"
SSH_READY=false

for i in $(seq 1 45); do
  if ssh $SSH_OPTS iwe@localhost "echo ok" 2>/dev/null | grep -q ok; then
    SSH_READY=true
    TIME_SSH=$(date +%s)
    BOOT_TIME=$((TIME_SSH - TIME_CREATE))
    echo "  ✓ SSH ready (boot time: ${BOOT_TIME}s)"
    break
  fi
  printf "."
  sleep 2
done
echo ""

if ! $SSH_READY; then
  echo "ERROR: SSH timeout (90s). VM may not have booted."
  echo "  Check: tail -f /tmp/qemu-$$.log"
  exit 1
fi

# =========================================================================
# Step 4: Run tests
# =========================================================================
echo ""
echo "--- Step 4: Run Tests ---"

# Upload secrets if available
SECRETS_DIR="$HOME/.iwe-test-vm/secrets"
if [ -d "$SECRETS_DIR" ] && [ -f "$SECRETS_DIR/.env" ]; then
  echo "  Uploading secrets..."
  ssh $SSH_OPTS iwe@localhost "mkdir -p ~/secrets" 2>/dev/null
  scp $SCP_OPTS "$SECRETS_DIR/.env" "iwe@localhost:~/secrets/.env" 2>/dev/null || true
  ssh $SSH_OPTS iwe@localhost "chmod 600 ~/secrets/.env" 2>/dev/null
  ssh $SSH_OPTS iwe@localhost "[ -f ~/secrets/.env ] && set -a && source ~/secrets/.env && set +a" 2>/dev/null || true
  echo "  ✓ Secrets uploaded"
fi

# Upload test-phases.sh
echo "  Uploading test-phases.sh..."
scp $SCP_OPTS "$SCRIPT_DIR/test-phases.sh" "iwe@localhost:~/test-phases.sh" 2>/dev/null || {
  echo "  ERROR: test-phases.sh upload failed"
  exit 1
}

# Upload and run firstboot if repo is missing
echo "  Checking repo..."
REPO_EXISTS=$(ssh $SSH_OPTS iwe@localhost "[ -d ~/IWE/FMT-exocortex-template/.git ] && echo yes || echo no" 2>/dev/null)
if [ "$REPO_EXISTS" = "no" ]; then
  echo "  Running firstboot (npm + git clone)..."
  scp $SCP_OPTS "$SCRIPT_DIR/packages-firstboot.sh" "iwe@localhost:~/packages-firstboot.sh" 2>/dev/null || {
    echo "  ⚠ Could not upload firstboot script"
  }
  FIRSTBOOT_LOG="/tmp/iwe-firstboot-$$.log"
  ssh $SSH_OPTS iwe@localhost "bash ~/packages-firstboot.sh" >"$FIRSTBOOT_LOG" 2>&1 || true
  grep -E '===|✓|✗|⚠|→' "$FIRSTBOOT_LOG" 2>/dev/null || true
  # Verify repo was actually cloned
  if ssh $SSH_OPTS iwe@localhost "[ -d ~/IWE/FMT-exocortex-template/.git ]" 2>/dev/null; then
    echo "  ✓ Repo cloned successfully"
  else
    echo "  ✗ Repo NOT cloned after firstboot — will skip test phases"
  fi
  rm -f "$FIRSTBOOT_LOG"
else
  echo "  ✓ Repo already present"
fi

# Run requested phase
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

  ssh $SSH_OPTS iwe@localhost "cd ~/IWE/FMT-exocortex-template && source ~/test-phases.sh && $func" 2>&1 || true
}

case "$RUN_PHASE" in
  1)    run_phase 1 "Clean Install" "phase1_setup" ;;
  2)    run_phase 2 "Update" "phase2_update" ;;
  3|smoke) run_phase 3 "AI Smoke" "phase3_ai_smoke" ;;
  4)    run_phase 4 "CI + Migrations" "phase4_ci" ;;
  all)
    run_phase 1 "Clean Install" "phase1_setup"
    run_phase 2 "Update" "phase2_update"
    run_phase 3 "AI Smoke" "phase3_ai_smoke"
    run_phase 4 "CI + Migrations" "phase4_ci"
    ;;
  *) echo "ERROR: invalid phase: $RUN_PHASE"; exit 1 ;;
esac

# Parse results from the tee'd output
TOTAL_PASS=$(grep -c '\[OK\]' "$REPORT" 2>/dev/null || echo "0")
TOTAL_FAIL=$(grep -c '\[FAIL\]' "$REPORT" 2>/dev/null || echo "0")

# =========================================================================
# Step 5: Report
# =========================================================================
echo ""
echo "========================================="
echo " IWE Golden Image Test Report"
echo "========================================="
echo ""
echo "  Version:    $REPO_VERSION"
echo "  Phase:      $RUN_PHASE"
echo "  Create VM:  ${ELAPSED}s"
echo "  Boot time:  ${BOOT_TIME}s"
echo "  Passed:     $TOTAL_PASS"
echo "  Failed:     $TOTAL_FAIL"
echo "  Report:     $REPORT"
echo ""

if $KEEP_VM; then
  echo "  VM KEPT for debugging."
  echo "  SSH:  ssh $SSH_OPTS iwe@localhost"
  echo "  Kill: kill $VM_PID ; rm $TEST_IMAGE"
  # Don't cleanup
  trap - EXIT
else
  echo "  Cleaning up..."
fi

echo "========================================="

exit ${TOTAL_FAIL:-0}
