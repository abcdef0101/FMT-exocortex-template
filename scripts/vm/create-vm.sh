#!/usr/bin/env bash
# create-vm.sh — создание тестовой VM для IWE
# Требует: qemu-kvm, libvirt, cloud-image-utils
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
VM_NAME="iwe-test"
VM_DIR="$HOME/.iwe-test-vm"
SSH_KEY="$HOME/.ssh/id_ed25519_iwe_test"
VM_IMAGE="noble-server-cloudimg-amd64.img"
VM_DISK="$VM_DIR/${VM_NAME}.qcow2"
VM_SEED="$VM_DIR/seed.img"
VM_RAM=4096
VM_CPUS=2
VM_DISK_SIZE="20G"

echo "========================================="
echo " IWE Test VM — Create"
echo "========================================="

# === Pre-flight checks ===
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "ERROR: qemu-system-x86_64 not found. Run: sudo apt install qemu-kvm" >&2; exit 1; }
command -v virsh >/dev/null 2>&1 || { echo "ERROR: virsh not found. Run: sudo apt install libvirt-clients" >&2; exit 1; }
command -v cloud-localds >/dev/null 2>&1 || { echo "ERROR: cloud-localds not found. Run: sudo apt install cloud-image-utils" >&2; exit 1; }

# Check if libvirtd is accessible
virsh list >/dev/null 2>&1 || { echo "ERROR: libvirtd not accessible. Run: sudo systemctl start libvirtd && sudo usermod -aG libvirt $USER" >&2; exit 1; }

# Detect bridge availability — use user-mode networking if no bridge
NETWORK_TYPE="user"
VNC_PORT=5900

# Try to find an active bridge
ACTIVE_NET=$(virsh net-list --name 2>/dev/null | grep -v "^$" | head -1 || true)
if [ -n "$ACTIVE_NET" ]; then
  # Extract bridge name (handles both name="x" and name='x')
  BRIDGE_NAME=$(virsh net-dumpxml "$ACTIVE_NET" 2>/dev/null | grep '<bridge ' | sed "s/.*bridge[^a-z]*name=['\"]\\([^'\"]*\\)['\"].*/\\1/" || true)
  if [ -n "$BRIDGE_NAME" ] && [ "$BRIDGE_NAME" != "$(virsh net-dumpxml "$ACTIVE_NET" 2>/dev/null | grep '<bridge ')" ]; then
    BRIDGE_IP=$(ip -4 addr show "$BRIDGE_NAME" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1 || true)
    if [ -n "$BRIDGE_IP" ]; then
      NETWORK_TYPE="bridge"
      echo "  Using bridge: $BRIDGE_NAME ($BRIDGE_IP)"
    fi
  fi
fi

if [ "$NETWORK_TYPE" = "user" ]; then
  echo "  Using user-mode networking (SSH access via port forwarding on localhost:2222)"
  # Clean up any leftover port forward
  ssh-keygen -R "[localhost]:2222" 2>/dev/null || true
fi

# === SSH key ===
if [ ! -f "$SSH_KEY" ]; then
  echo "Creating SSH key: $SSH_KEY"
  ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "${VM_NAME}" -q
fi
SSH_PUB=$(cat "${SSH_KEY}.pub")

echo "  SSH key: $(ssh-keygen -l -f "$SSH_KEY" 2>/dev/null | awk '{print $1, $3}')"

# === Directories ===
mkdir -p "$VM_DIR"

# === Download cloud image (cached) ===
if [ ! -f "$VM_DIR/$VM_IMAGE" ]; then
  echo "Downloading Ubuntu 24.04 cloud image..."
  wget -q --show-progress -O "$VM_DIR/$VM_IMAGE" \
    "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
else
  echo "  Using cached image: $VM_DIR/$VM_IMAGE"
fi

# === Generate cloud-init seed ===
echo "Generating cloud-init seed with SSH key..."
TMP_USERDATA=$(mktemp)
sed "s|PLACEHOLDER_SSH_KEY|$SSH_PUB|" "$SCRIPT_DIR/user-data.yaml" > "$TMP_USERDATA"
cloud-localds "$VM_SEED" "$TMP_USERDATA" 2>/dev/null
rm -f "$TMP_USERDATA"
echo "  seed: $VM_SEED"

# === Create VM disk ===
if [ -f "$VM_DISK" ]; then
  echo "  VM disk exists: $VM_DISK"
  echo "  Run destroy-vm.sh first to recreate."
  exit 1
fi

echo "Creating VM disk ($VM_DISK_SIZE)..."
qemu-img create -f qcow2 -F qcow2 -b "$VM_DIR/$VM_IMAGE" "$VM_DISK" "$VM_DISK_SIZE" >/dev/null

# === virt-install ===
echo ""
echo "Creating VM: $VM_NAME ($VM_RAM MB, $VM_CPUS CPUs)"
echo ""

NET_ARGS=""
if [ "$NETWORK_TYPE" = "user" ]; then
  NET_ARGS="--network user,model=virtio"
else
  NET_ARGS="--network bridge=${BRIDGE_NAME},model=virtio"
fi

sudo virt-install \
  --name "$VM_NAME" \
  --memory "$VM_RAM" \
  --vcpus "$VM_CPUS" \
  --disk "$VM_DISK",format=qcow2 \
  --disk "$VM_SEED",device=cdrom \
  --os-variant ubuntu24.04 \
  $NET_ARGS \
  --graphics none \
  --import \
  --noautoconsole \
  --wait=-1

echo ""
echo "========================================="
echo " VM Created: $VM_NAME"
echo "========================================="
echo ""
if [ "$NETWORK_TYPE" = "user" ]; then
  echo "SSH access (user-mode):"
  echo "  sudo virsh qemu-monitor-command $VM_NAME --hmp 'hostfwd_add tcp::2222-:22' 2>/dev/null || true"
  echo "  ssh -i $SSH_KEY -o StrictHostKeyChecking=no -p 2222 iwe@localhost"
else
  echo "IP address:"
  virsh domifaddr "$VM_NAME" --source agent 2>/dev/null || echo "  (waiting for cloud-init... run: virsh domifaddr $VM_NAME --source agent)"
  echo "SSH:  ssh -i $SSH_KEY iwe@<IP>"
fi
echo "Test: bash scripts/vm/run-full-test.sh"
