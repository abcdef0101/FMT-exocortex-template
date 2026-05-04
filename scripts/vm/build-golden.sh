#!/usr/bin/env bash
# build-golden.sh — однократная сборка золотого образа IWE
#
# Метод:
#   1. qemu-img create -b base.img → golden.qcow2 (COW)
#   2. Cloud-init seed (минимальный: user iwe + SSH ключ)
#   3. Boot VM, ждать cloud-init + SSH
#   4. SSH: upload + run provision (apt + npm + git clone)
#   5. Shutdown, snapshot "provisioned", sha256sum
#
# Проблема cloud-init packages в user-mode: DNS в QEMU user-mode часто ломает
# apt-get внутри cloud-init, вызывая таймауты. Поэтому устанавливаем всё через SSH.
#
# Использование:
#   bash scripts/vm/build-golden.sh [--version 0.25.1] [--force] [--ssh-key PATH]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

BASE_URL="https://cloud-images.ubuntu.com/noble/current"
BASE_IMAGE_NAME="noble-server-cloudimg-amd64.img"
CACHE_DIR="$HOME/.cache/iwe-golden"
SSH_KEY="$HOME/.ssh/id_ed25519_iwe_test"
FORCE=false
REPO_VERSION=""

while [ $# -gt 0 ]; do
  case "$1" in
    --version) REPO_VERSION="$2"; shift 2 ;;
    --version=*) REPO_VERSION="${1#*=}"; shift ;;
    --force) FORCE=true; shift ;;
    --ssh-key) SSH_KEY="$2"; shift 2 ;;
    --ssh-key=*) SSH_KEY="${1#*=}"; shift ;;
    --help|-h) echo "Usage: build-golden.sh [--version V] [--force] [--ssh-key PATH]"; exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

[ -z "$REPO_VERSION" ] && REPO_VERSION=$(grep -m1 '^version:' "$ROOT_DIR/MANIFEST.yaml" 2>/dev/null | awk '{print $2}')
[ -z "$REPO_VERSION" ] && { echo "ERROR: cannot detect version. Use --version." >&2; exit 1; }

BASE_IMAGE="$CACHE_DIR/$BASE_IMAGE_NAME"
GOLDEN_IMAGE="$CACHE_DIR/iwe-golden-${REPO_VERSION}.qcow2"
GOLDEN_SHA256="$GOLDEN_IMAGE.sha256"
FIRSTBOOT_SCRIPT="$SCRIPT_DIR/packages-firstboot.sh"

SSH_PUB=$(cat "$SSH_KEY.pub")
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3 -o ServerAliveInterval=5"
SCP_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3 -q"

echo "========================================="
echo " IWE Golden Image Build"
echo "========================================="
echo "  Version: $REPO_VERSION"
echo "  Output:  $GOLDEN_IMAGE"
echo ""

for cmd in qemu-img qemu-system-x86_64 cloud-localds wget; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: $cmd not found" >&2; exit 1; }
done
[ ! -f "$SSH_KEY.pub" ] && { echo "ERROR: SSH key not found: $SSH_KEY.pub" >&2; exit 1; }
[ ! -f "$FIRSTBOOT_SCRIPT" ] && { echo "ERROR: $FIRSTBOOT_SCRIPT not found" >&2; exit 1; }

if [ -f "$GOLDEN_IMAGE" ]; then
  if $FORCE; then
    rm -f "$GOLDEN_IMAGE" "$GOLDEN_SHA256"
  else
    echo "  Golden image exists. Use --force to overwrite."
    exit 1
  fi
fi

mkdir -p "$CACHE_DIR"

# =========================================================================
# Step 1: Base image
# =========================================================================
echo "--- Step 1: Base Image ---"
if [ -f "$BASE_IMAGE" ]; then
  echo "  Cached: $BASE_IMAGE ($(du -sh "$BASE_IMAGE" | cut -f1))"
else
  echo "  Downloading..."
  wget -q --show-progress -O "$BASE_IMAGE" "$BASE_URL/$BASE_IMAGE_NAME"
fi

# =========================================================================
# Step 2: Create golden qcow2
# =========================================================================
echo "--- Step 2: Create golden qcow2 ---"
qemu-img create -f qcow2 -b "$BASE_IMAGE" -F qcow2 "$GOLDEN_IMAGE" 20G >/dev/null 2>&1
echo "  ✓ $GOLDEN_IMAGE"

# =========================================================================
# Step 3: Minimal cloud-init (user + SSH only, no packages)
# =========================================================================
echo "--- Step 3: Cloud-init seed (minimal) ---"

TMP_UD=$(mktemp)
cat > "$TMP_UD" <<ENDUD
#cloud-config
users:
  - name: iwe
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - $SSH_PUB
packages:
  - cloud-init
runcmd:
  - echo 'export PATH="\$HOME/.local/bin:\$HOME/.opencode/bin:\$HOME/.opencode/node_modules/.bin:\$PATH"' >> /home/iwe/.bashrc
  - echo 'export PATH="\$HOME/.local/bin:\$HOME/.opencode/bin:\$HOME/.opencode/node_modules/.bin:\$PATH"' >> /home/iwe/.profile
ENDUD

SEED_IMG="/tmp/iwe-golden-seed-$$.img"
cloud-localds "$SEED_IMG" "$TMP_UD" 2>/dev/null
rm -f "$TMP_UD"
echo "  ✓ Seed: $SEED_IMG ($(stat -c%s "$SEED_IMG") bytes)"

# =========================================================================
# Step 4: Boot VM
# =========================================================================
echo "--- Step 4: Boot VM ---"

PORT=2244
while ss -tlnp 2>/dev/null | grep -q ":$PORT "; do PORT=$((PORT + 1)); done

qemu-system-x86_64 -enable-kvm -m 4096 -smp 2 \
  -drive file="$GOLDEN_IMAGE",if=virtio \
  -cdrom "$SEED_IMG" \
  -netdev user,id=net0,hostfwd=tcp::${PORT}-:22,restrict=off \
  -device virtio-net,netdev=net0 \
  -display none -daemonize 2>/tmp/iwe-qemu-err-$$.log &

QEMU_PID=$!
SSH_OPTS="$SSH_OPTS -p $PORT"

cleanup_qemu() {
  kill "$QEMU_PID" 2>/dev/null || true
  sleep 1
  kill -9 "$QEMU_PID" 2>/dev/null || true
  rm -f "$SEED_IMG"
}
trap cleanup_qemu EXIT

echo "  QEMU PID: $QEMU_PID, Port: $PORT"

# Wait for cloud-init to create user and start SSH (~1-2 min)
echo -n "  Waiting for SSH:"
SSH_OK=false
for i in $(seq 1 90); do
  if ssh $SSH_OPTS iwe@localhost "echo ok" 2>/dev/null | grep -q ok; then
    SSH_OK=true
    echo " OK (${i}x3s)"
    break
  fi
  printf "."
  sleep 3
done
echo ""

if ! $SSH_OK; then
  echo "ERROR: SSH timeout. Cloud-init may have failed." >&2
  exit 1
fi

# =========================================================================
# Step 5: Remote provisioning (system packages + npm)
# =========================================================================
echo "--- Step 5: Provision ---"

PROVISION_LOG="/tmp/iwe-provision-$$.log"

# Create provision script
PROV_SCRIPT="/tmp/iwe-provision-script-$$.sh"
cat > "$PROV_SCRIPT" <<'PROVSCRIPT'
#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "Waiting for cloud-init to finish..."
sudo cloud-init status --wait 2>&1 || true
echo "Cloud-init done."

# Wait for apt locks
for i in $(seq 1 12); do
  if sudo fuser /var/lib/apt/lists/lock 2>/dev/null; then
    echo "  apt locked, waiting... ($i/12)"
    sleep 5
  else
    break
  fi
done

echo ""
echo "=== System Packages (Layer 1) ==="

echo "Updating apt..."
sudo apt-get update -qq 2>&1 | tail -1

echo "Installing base packages..."
sudo apt-get install -y -qq \
  git gh curl wget ruby expect jq shellcheck \
  vim mc tmux build-essential ca-certificates gnupg \
  python3 python3-yaml software-properties-common \
  2>&1 | tail -3

echo "Installing Node.js 20 LTS..."
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash - 2>&1 | tail -1
sudo apt-get install -y -qq nodejs 2>&1 | tail -1
sudo npm install -g -q npm@latest 2>&1 | tail -1

echo "Installing neovim..."
sudo add-apt-repository -y ppa:neovim-ppa/stable 2>&1 | tail -1
sudo apt-get update -qq 2>&1 | tail -1
sudo apt-get install -y -qq neovim 2>&1 | tail -1

echo "Creating directories..."
mkdir -p ~/IWE ~/.config/gh ~/.local/bin ~/.opencode

echo ""
echo "=== Package Verification ==="
for pkg in git gh ruby expect jq shellcheck vim mc tmux curl build-essential python3 python3-yaml neovim nodejs npm; do
  dpkg -l "$pkg" 2>/dev/null | grep -q "^ii" && echo "  ✓ $pkg" || echo "  ✗ $pkg MISSING"
done
echo "Node.js: $(node --version 2>/dev/null || echo 'missing')"
echo "npm:     $(npm --version 2>/dev/null || echo 'missing')"

echo ""
echo "=== NPM Packages (Layer 2) ==="
bash ~/packages-firstboot.sh 2>&1
PROVSCRIPT

# Upload provision script and firstboot script
scp $SCP_OPTS -P "$PORT" "$PROV_SCRIPT" "iwe@localhost:~/provision.sh" 2>/dev/null
scp $SCP_OPTS -P "$PORT" "$FIRSTBOOT_SCRIPT" "iwe@localhost:~/packages-firstboot.sh" 2>/dev/null

# Run provision, capture output with proper error handling
set +o pipefail
ssh $SSH_OPTS -p "$PORT" -o ServerAliveInterval=10 iwe@localhost "bash ~/provision.sh" >"$PROVISION_LOG" 2>&1
PROVISION_RC=$?
set -o pipefail

# Show provision output
if [ -s "$PROVISION_LOG" ]; then
  while IFS= read -r line; do echo "    $line"; done < "$PROVISION_LOG"
fi

if [ "$PROVISION_RC" -ne 0 ]; then
  echo "  ✗ Provision FAILED (rc=$PROVISION_RC)"
  echo "  Full log: $PROVISION_LOG"
  exit 1
fi

echo "  ✓ Provision complete"

# Cleanup temp provision script
rm -f "$PROV_SCRIPT"

# =========================================================================
# Step 6: Clean shutdown
# =========================================================================
echo "--- Step 6: Shutdown ---"
ssh $SSH_OPTS -p "$PORT" iwe@localhost "sudo shutdown -h now" 2>/dev/null || true

echo -n "  Waiting for VM to stop:"
for i in $(seq 1 30); do
  kill -0 "$QEMU_PID" 2>/dev/null || break
  printf "."
  sleep 2
done
kill -0 "$QEMU_PID" 2>/dev/null && kill -9 "$QEMU_PID" 2>/dev/null || true
echo " OK"

trap - EXIT
rm -f "$SEED_IMG" /tmp/iwe-nodejs-setup-$$.sh "$PROVISION_LOG"

# =========================================================================
# Step 7: Snapshot
# =========================================================================
echo "--- Step 7: Snapshot ---"
# Wait for disk flush
sleep 2
if qemu-img snapshot -c "provisioned" "$GOLDEN_IMAGE" 2>&1; then
  echo "  ✓ Snapshot 'provisioned' created"
else
  echo "  ✗ Snapshot failed — continuing without snapshot"
fi

# =========================================================================
# Step 8: Checksum
# =========================================================================
echo "--- Step 8: Checksum ---"
sha256sum "$GOLDEN_IMAGE" > "$GOLDEN_SHA256"
CHECKSUM=$(cut -d' ' -f1 "$GOLDEN_SHA256")

# =========================================================================
# Report
# =========================================================================
echo ""
echo "========================================="
echo " ✓ Golden Image Built"
echo "========================================="
echo "  Image:    $GOLDEN_IMAGE ($(du -sh "$GOLDEN_IMAGE" | cut -f1))"
echo "  SHA256:   ${CHECKSUM:0:16}..."
echo "  Snapshot: provisioned"
echo ""
echo "  Verify:   bash scripts/vm/verify-golden.sh --image $GOLDEN_IMAGE"
echo "  Test:     bash scripts/vm/test-from-golden.sh --version $REPO_VERSION"
