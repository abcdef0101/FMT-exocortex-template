#!/usr/bin/env bash
# run-full-test.sh — полный цикл тестирования IWE в VM
# 1. Создать VM (если не существует)
# 2. Provision (установить IWE)
# 3. Запустить все тесты
# 4. OpenCode smoke-test
# 5. Отчёт
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
VM_NAME="iwe-test"
SSH_KEY="$HOME/.ssh/id_ed25519_iwe_test"
RESULTS_DIR="$ROOT_DIR/scripts/vm/results"

mkdir -p "$RESULTS_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT="$RESULTS_DIR/report-$TIMESTAMP.txt"

exec > >(tee "$REPORT") 2>&1

echo "========================================="
echo " IWE Full Test — $TIMESTAMP"
echo "========================================="
echo ""

# === Step 0: Ensure VM exists ===
if ! virsh list --name --all 2>/dev/null | grep -q "^${VM_NAME}$"; then
  echo "VM not found. Creating..."
  bash "$SCRIPT_DIR/create-vm.sh"
  bash "$SCRIPT_DIR/provision.sh"
else
  VM_STATE=$(virsh domstate "$VM_NAME" 2>/dev/null || echo "unknown")
  if [ "$VM_STATE" != "running" ]; then
    echo "Starting VM..."
    virsh start "$VM_NAME" 2>/dev/null || true
    sleep 30  # wait for boot + cloud-init
  fi
  # Re-provision (idempotent — skips existing)
  bash "$SCRIPT_DIR/provision.sh"
fi

# === Get VM IP ===
VM_IP=$(virsh domifaddr "$VM_NAME" --source agent 2>/dev/null | grep -oP '(\d+\.\d+\.\d+\.\d+)' | head -1)
SSH_PORT=22
SSH_HOST="$VM_IP"

if [ -z "$VM_IP" ]; then
  VM_IP=$(virsh net-dhcp-leases default 2>/dev/null | grep "$VM_NAME" | awk '{print $5}' | cut -d/ -f1 || true)
fi
if [ -z "$VM_IP" ]; then
  SSH_PORT=2222
  SSH_HOST="localhost"
fi

SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=5"
[ "$SSH_PORT" != "22" ] && SSH_OPTS="$SSH_OPTS -p $SSH_PORT"

SSH="ssh $SSH_OPTS iwe@$SSH_HOST"

VM_LABEL="localhost:$SSH_PORT (user-mode)"
if [ "$SSH_PORT" = "22" ]; then
  VM_LABEL="$SSH_HOST (bridge)"
fi
echo ""
echo "  VM: $VM_LABEL"
echo ""

# === Step 1: Unit tests ===
echo "=== [1/5] Unit + Integration Tests ==="
$SSH "cd ~/IWE/FMT-exocortex-template && bash scripts/test/run-phase0.sh" 2>&1 | tail -5
PASS_COUNT=$($SSH "cd ~/IWE/FMT-exocortex-template && bash scripts/test/run-phase0.sh 2>&1" | grep "Result:" | grep -oP '\d+(?= passed)' || echo "?")
echo "  Unit tests: $PASS_COUNT/14 PASS"
echo ""

# === Step 2: E2E tests ===
echo "=== [2/5] E2E Tests ==="
$SSH "cd ~/IWE/FMT-exocortex-template && bash scripts/test/run-e2e.sh" 2>&1 | tail -3
E2E_PASS=$($SSH "cd ~/IWE/FMT-exocortex-template && bash scripts/test/run-e2e.sh 2>&1" | grep "Result:" | grep -oP '\d+(?= passed)' || echo "?")
echo "  E2E tests: $E2E_PASS/5 PASS"
echo ""

# === Step 3: CI enforcement ===
echo "=== [3/5] CI Enforcement ==="
$SSH "cd ~/IWE/FMT-exocortex-template && bash scripts/enforce-semver.sh" 2>&1 | tail -3
CI_RC=$($SSH "cd ~/IWE/FMT-exocortex-template && bash scripts/enforce-semver.sh >/dev/null 2>&1 && echo 0 || echo 1")
[ "$CI_RC" = "0" ] && echo "  CI checks: PASS" || echo "  CI checks: FAIL"
echo ""

# === Step 4: OpenCode smoke test ===
echo "=== [4/5] OpenCode Smoke Test ==="
SMOKE_RESULT="SKIP (no API key)"

# Check if OpenCode is installed and API key is available
HAS_OPENCODE=$($SSH "command -v opencode >/dev/null 2>&1 && echo yes || echo no")
HAS_API_KEY=$($SSH "[ -n \"\${OPENAI_API_KEY:-}\" ] && echo yes || echo no")

if [ "$HAS_OPENCODE" = "yes" ] && [ "$HAS_API_KEY" = "yes" ]; then
  SMOKE_OUTPUT=$($SSH "cd ~/IWE/FMT-exocortex-template && echo 'say exactly: IWE test VM OK' | opencode --print 2>&1 | head -5" 2>/dev/null || echo "ERROR")
  if echo "$SMOKE_OUTPUT" | grep -q "IWE test VM OK"; then
    SMOKE_RESULT="PASS"
  else
    SMOKE_RESULT="FAIL ($SMOKE_OUTPUT)"
  fi
else
  SMOKE_RESULT="SKIP (opencode=$HAS_OPENCODE, api_key=$HAS_API_KEY)"
fi
echo "  OpenCode smoke: $SMOKE_RESULT"
echo ""

# === Step 5: Update check ===
echo "=== [5/5] Update Mechanism ==="
$SSH "cd ~/IWE/FMT-exocortex-template && bash update.sh --check 2>&1" | tail -3
UPDATE_RC=$($SSH "cd ~/IWE/FMT-exocortex-template && bash update.sh --check >/dev/null 2>&1 && echo 0 || echo 1")
[ "$UPDATE_RC" = "0" ] && echo "  Update: up-to-date" || echo "  Update: changes available"
echo ""

# === Report ===
echo "========================================="
echo " Test Report — $TIMESTAMP"
echo "========================================="
echo ""
echo "  VM:        $VM_NAME ($VM_IP)"
echo "  Unit:      $PASS_COUNT/14 PASS"
echo "  E2E:       $E2E_PASS/5 PASS"
echo "  CI:        $([ "$CI_RC" = "0" ] && echo 'PASS' || echo 'FAIL')"
echo "  OpenCode:  $SMOKE_RESULT"
echo "  Update:    $([ "$UPDATE_RC" = "0" ] && echo 'up-to-date' || echo 'changes available')"
echo ""
echo "  Report:    $REPORT"
echo "  SSH:       ssh -i $SSH_KEY iwe@$VM_IP"
echo ""
echo "  Skipped - need Claude Code API: Day Open, Day Close, Week Close"
echo "========================================="
