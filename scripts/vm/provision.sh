#!/usr/bin/env bash
# provision.sh — настроить IWE внутри VM после boot
# Запускать после create-vm.sh, когда cloud-init завершён
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
VM_NAME="iwe-test"
SSH_KEY="$HOME/.ssh/id_ed25519_iwe_test"
SECRETS_DIR="$HOME/.iwe-test-vm/secrets"
REPO_URL="https://github.com/abcdef0101/FMT-exocortex-template.git"

echo "========================================="
echo " IWE Test VM — Provision"
echo "========================================="

# === Get VM IP ===
# Try bridge first, then user-mode (localhost port forward)
VM_IP=$(virsh domifaddr "$VM_NAME" --source agent 2>/dev/null | grep -oP '(\d+\.\d+\.\d+\.\d+)' | head -1)
SSH_PORT=22
SSH_HOST="$VM_IP"

if [ -z "$VM_IP" ]; then
  VM_IP=$(virsh net-dhcp-leases default 2>/dev/null | grep "$VM_NAME" | awk '{print $5}' | cut -d/ -f1 || true)
fi

if [ -z "$VM_IP" ]; then
  # User-mode networking — use port forwarding
  echo "  Setting up port forwarding (user-mode networking)..."
  sudo virsh qemu-monitor-command "$VM_NAME" --hmp 'hostfwd_add tcp::2222-:22' 2>/dev/null || true
  VM_IP="localhost"
  SSH_PORT=2222
  SSH_HOST="localhost"
fi

SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=3"
if [ "$SSH_PORT" != "22" ]; then
  SSH_OPTS="$SSH_OPTS -p $SSH_PORT"
fi

SSH_LABEL="localhost:$SSH_PORT (user-mode)"
if [ "$SSH_PORT" = "22" ]; then
  SSH_LABEL="$SSH_HOST (bridge)"
fi
echo "  SSH: $SSH_LABEL"

# === Wait for SSH ===
echo "  Waiting for SSH..."
for i in $(seq 1 30); do
  if ssh $SSH_OPTS "iwe@$SSH_HOST" "echo ok" 2>/dev/null | grep -q ok; then
    break
  fi
  [ "$i" -eq 30 ] && { echo "ERROR: SSH timeout" >&2; exit 1; }
  sleep 2
done
echo "  SSH: ready"

# === Upload secrets ===
if [ -d "$SECRETS_DIR" ] && [ -f "$SECRETS_DIR/.env" ]; then
  echo "  Uploading secrets..."
  ssh $SSH_OPTS "iwe@$SSH_HOST" "mkdir -p ~/secrets" 2>/dev/null
  scp $SSH_OPTS -q "$SECRETS_DIR/.env" "iwe@$SSH_HOST:~/secrets/.env" 2>/dev/null || true
  ssh $SSH_OPTS "iwe@$SSH_HOST" "chmod 600 ~/secrets/.env" 2>/dev/null
  echo "  Secrets: transferred"
else
  echo "  Secrets: not found - skipping API key tests"
fi

# === Clone and setup IWE ===
echo ""
echo "  === Cloning and installing IWE ==="

ssh $SSH_OPTS "iwe@$SSH_HOST" bash -s << 'ENDSSH'
set -euo pipefail

REQUIRED_BRANCH="0.25.1"
REPO_URL="https://github.com/abcdef0101/FMT-exocortex-template.git"

# Source secrets if available
[ -f ~/secrets/.env ] && set -a && source ~/secrets/.env && set +a

# Auth GitHub
if [ -n "${GH_TOKEN:-}" ]; then
  echo "$GH_TOKEN" | gh auth login --with-token 2>/dev/null || true
fi

# Clone repo — требует git clone, не tar copy
cd ~/IWE
if [ -d FMT-exocortex-template ]; then
  # Проверить что ветка правильная
  ACTUAL_BRANCH=$(git -C FMT-exocortex-template branch --show-current 2>/dev/null || echo "detached")
  if [ "$ACTUAL_BRANCH" != "$REQUIRED_BRANCH" ]; then
    echo "  Wrong branch ($ACTUAL_BRANCH), re-cloning $REQUIRED_BRANCH..."
    rm -rf FMT-exocortex-template
  fi
fi

if [ ! -d FMT-exocortex-template ]; then
  echo "  Cloning branch $REQUIRED_BRANCH..."
  git clone --branch "$REQUIRED_BRANCH" "$REPO_URL" 2>&1 | tail -1
fi

cd FMT-exocortex-template

# Verify branch
ACTUAL_BRANCH=$(git branch --show-current)
if [ "$ACTUAL_BRANCH" != "$REQUIRED_BRANCH" ]; then
  echo "ERROR: Expected branch $REQUIRED_BRANCH, got $ACTUAL_BRANCH" >&2
  exit 1
fi
echo "✓ Branch: $ACTUAL_BRANCH ($(git rev-parse --short HEAD))"

# Helper: validate workspace after setup
check_workspace() {
  local ws="$1"
  local ok=0
  [ -d "workspaces/$ws" ] || { echo "  ✗ workspace dir missing: $ws"; ok=1; }
  [ -f "workspaces/$ws/CLAUDE.md" ] || { echo "  ✗ CLAUDE.md missing"; ok=1; }
  [ -f "workspaces/$ws/memory/MEMORY.md" ] || { echo "  ✗ MEMORY.md missing"; ok=1; }
  [ -L "workspaces/$ws/memory/persistent-memory" ] || { echo "  ✗ symlink missing"; ok=1; }
  [ -e "workspaces/$ws/memory/persistent-memory" ] || { echo "  ✗ symlink broken"; ok=1; }
  [ "$ok" -eq 0 ] && echo "  ✓ workspace valid: $ws"
  return $ok
}

# === Phase 1: Minimal install (--core), verify, then delete ===
echo ""
echo "  === Phase 1: setup.sh --core ==="
expect -c '
set timeout 30
spawn bash setup.sh --core
expect "GitHub username"          { send "vm-test\r" }
expect "Workspace name"           { send "iwe2-core\r" }
expect "Data Policy (y/n)"       { send "y" }
expect "Continue with setup"      { send "y" }
expect eof
lassign [wait] pid spawnid os_error_flag exit_code
exit $exit_code
'
CORE_RC=$?
if [ "$CORE_RC" -eq 0 ] && check_workspace iwe2-core; then
  echo "  ✓ Phase 1 PASSED"
  rm -rf workspaces/iwe2-core
else
  echo "  ✗ Phase 1 FAILED (rc=$CORE_RC)"
fi

# === Phase 2: Full install, verify, keep ===
echo ""
echo "  === Phase 2: setup.sh (full) ==="
expect -c '
set timeout 60
spawn bash setup.sh
expect "GitHub username"          { send "vm-test\r" }
expect "Workspace name"           { send "iwe2\r" }
expect "Claude CLI path"          { send "\r" }
expect "Strategist launch"        { send "\r" }
expect "Timezone description"     { send "\r" }
expect "Data Policy (y/n)"       { send "y" }
expect "Continue with setup"      { send "y" }
expect eof
lassign [wait] pid spawnid os_error_flag exit_code
exit $exit_code
'
FULL_RC=$?
if [ "$FULL_RC" -eq 0 ] && check_workspace iwe2; then
  echo "  ✓ Phase 2 PASSED"
  echo ""
  echo "  Full mode extras:"
  [ -d "../PACK-digital-platform" ] && echo "    ✓ PACK cloned" || echo "    ⚠ PACK not cloned"
  ls roles/*/install.sh >/dev/null 2>&1 && echo "    ✓ role installers present"
else
  echo "  ✗ Phase 2 FAILED (rc=$FULL_RC)"
fi

echo ""
echo "✓ IWE installed — branch $REQUIRED_BRANCH"
ENDSSH

echo ""
echo "========================================="
echo " Provision Complete"
echo "========================================="
echo ""
if [ "$SSH_PORT" != "22" ]; then
  echo "SSH:  ssh $SSH_OPTS iwe@localhost"
else
  echo "SSH:  ssh $SSH_OPTS iwe@$SSH_HOST"
fi
echo "Test: bash scripts/vm/run-full-test.sh"
