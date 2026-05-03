#!/usr/bin/env bash
# run-full-test.sh — полный цикл тестирования IWE в VM
#
# Фазы:
#   1. Чистая установка (validate, manifest, copy-once, structure, symlink, run-phase0)
#   2. Обновление (check, upstream mock, apply, merge, run-e2e)
#   3. OpenCode AI smoke (basic, file read, context, update check)
#   4. CI + Миграции (enforce-semver, migrations, checksums, never-touch)
#
# Использование:
#   bash scripts/vm/run-full-test.sh           # Все фазы
#   bash scripts/vm/run-full-test.sh --phase 1 # Только фаза 1
#   bash scripts/vm/run-full-test.sh --smoke   # Только AI smoke
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
VM_NAME="iwe-test"
SSH_KEY="$HOME/.ssh/id_ed25519_iwe_test"
RESULTS_DIR="$ROOT_DIR/scripts/vm/results"

mkdir -p "$RESULTS_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT="$RESULTS_DIR/report-$TIMESTAMP.txt"

# Parse args
RUN_PHASE="all"
for arg in "$@"; do
  case "$arg" in
    --phase) RUN_PHASE="${2:-all}"; shift ;;
    --phase=*) RUN_PHASE="${arg#*=}" ;;
    --smoke) RUN_PHASE="3" ;;
    --help|-h)
      echo "Usage: run-full-test.sh [OPTIONS]"
      echo "  --phase N    Run specific phase (1-4, или 'all')"
      echo "  --smoke      AI smoke test only (phase 3)"
      echo "  --help       This help"
      exit 0
      ;;
  esac
  shift 2>/dev/null || true
done

exec > >(tee "$REPORT") 2>&1

echo "========================================="
echo " IWE Full Test — $TIMESTAMP"
echo "========================================="
echo ""

# Summarize results
declare -A PHASE_RESULTS
declare -A PHASE_PASSES
declare -A PHASE_FAILS

# =========================================================================
# VM connectivity
# =========================================================================

# Ensure VM exists and is running
if ! virsh list --name --all 2>/dev/null | grep -q "^${VM_NAME}$" 2>/dev/null; then
  echo "VM '$VM_NAME' not found."
  echo "Create it first: bash scripts/vm/create-vm.sh"
  exit 1
fi

VM_STATE=$(virsh domstate "$VM_NAME" 2>/dev/null || echo "unknown")
if [ "$VM_STATE" != "running" ]; then
  echo "Starting VM..."
  virsh start "$VM_NAME" 2>/dev/null || true
  sleep 30
fi

# Get VM IP
VM_IP=$(virsh domifaddr "$VM_NAME" --source agent 2>/dev/null | grep -oP '(\d+\.\d+\.\d+\.\d+)' | head -1)
SSH_PORT=22
SSH_HOST="$VM_IP"

if [ -z "$VM_IP" ]; then
  VM_IP=$(virsh net-dhcp-leases default 2>/dev/null | grep "$VM_NAME" | awk '{print $5}' | cut -d/ -f1 || true)
fi
if [ -z "$VM_IP" ]; then
  sudo virsh qemu-monitor-command "$VM_NAME" --hmp 'hostfwd_add tcp::2222-:22' 2>/dev/null || true
  SSH_PORT=2222
  SSH_HOST="localhost"
fi

SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=5"
[ "$SSH_PORT" != "22" ] && SSH_OPTS="$SSH_OPTS -p $SSH_PORT"
SSH="ssh $SSH_OPTS iwe@$SSH_HOST"

VM_LABEL="localhost:$SSH_PORT (user-mode)"
[ "$SSH_PORT" = "22" ] && VM_LABEL="$SSH_HOST (bridge)"

echo "VM: $VM_LABEL"
echo ""

# =========================================================================
# Upload test phases script to VM
# =========================================================================
echo "--- Uploading test scripts ---"
scp $SSH_OPTS -q "$SCRIPT_DIR/test-phases.sh" "iwe@$SSH_HOST:~/test-phases.sh" 2>/dev/null || {
  echo "  WARN: Could not upload test-phases.sh. VM may not be provisioned."
  echo "  Run: bash scripts/vm/provision.sh"
  exit 1
}
echo "  test-phases.sh uploaded"
echo ""

# =========================================================================
# Run phases
# =========================================================================
run_phase() {
  local num="$1"
  local name="$2"
  local func="$3"

  echo ""
  echo "========================================="
  echo " Phase $num: $name"
  echo "========================================="

  $SSH "source ~/test-phases.sh && $func" 2>&1

  # Parse results from output
  local pass_count fail_count
  pass_count=$(grep -c '\[OK\]' "$REPORT" 2>/dev/null | tail -1 || echo "0")
  fail_count=$(grep -c '\[FAIL\]' "$REPORT" 2>/dev/null | tail -1 || echo "0")

  PHASE_PASSES[$num]=$pass_count
  PHASE_FAILS[$num]=$fail_count
}

if [ "$RUN_PHASE" = "all" ] || [ "$RUN_PHASE" = "1" ]; then
  run_phase 1 "Clean Install" "phase1_setup"
fi

if [ "$RUN_PHASE" = "all" ] || [ "$RUN_PHASE" = "2" ]; then
  run_phase 2 "Update" "phase2_update"
fi

if [ "$RUN_PHASE" = "all" ] || [ "$RUN_PHASE" = "3" ] || [ "$RUN_PHASE" = "smoke" ]; then
  run_phase 3 "AI Smoke" "phase3_ai_smoke"
fi

if [ "$RUN_PHASE" = "all" ] || [ "$RUN_PHASE" = "4" ]; then
  run_phase 4 "CI + Migrations" "phase4_ci"
fi

# =========================================================================
# Report
# =========================================================================
echo ""
echo "========================================="
echo " IWE Full Test Report — $TIMESTAMP"
echo "========================================="
echo ""
echo "  VM:        $VM_LABEL"

for num in 1 2 3 4; do
  if [ -n "${PHASE_PASSES[$num]:-}" ]; then
    echo "  Phase $num:   ${PHASE_PASSES[$num]:-0} passed, ${PHASE_FAILS[$num]:-0} failed"
  fi
done

echo ""
echo "  Report:    $REPORT"
echo "  SSH:       $SSH iwe@$SSH_HOST"
echo ""

# Skipped tests
echo "  Manual smoke (skipped):"
echo "    - Day Open → DayPlan creation   (needs /day-open skill)"
echo "    - Day Close → daily report      (needs /day-close skill)"
echo "    - Role Strategist auto-install  (needs launchd/systemd)"
echo ""
echo "  See: scripts/test/e2e/SMOKE-TEST.md"
echo "========================================="
