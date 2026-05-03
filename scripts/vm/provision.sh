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

# Source secrets if available
[ -f ~/secrets/.env ] && set -a && source ~/secrets/.env && set +a

# Auth GitHub
if [ -n "${GH_TOKEN:-}" ]; then
  echo "$GH_TOKEN" | gh auth login --with-token 2>/dev/null || true
fi

# Clone repo
cd ~/IWE
if [ ! -d FMT-exocortex-template ]; then
  git clone https://github.com/abcdef0101/FMT-exocortex-template.git
fi
cd FMT-exocortex-template

# Setup workspace via manifest
source scripts/lib/manifest-lib.sh
WORKSPACE_FULL_PATH="$HOME/IWE/workspaces/iwe2"
export WORKSPACE_FULL_PATH
apply_manifest seed/manifest.yaml false 2>&1 | tail -3

# Create workspace symlink
rm -f workspaces/CURRENT_WORKSPACE 2>/dev/null || true
ln -sf "$WORKSPACE_FULL_PATH" workspaces/CURRENT_WORKSPACE

echo "✓ IWE installed"
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
