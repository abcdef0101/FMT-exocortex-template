#!/usr/bin/env bash
# verify-golden.sh — проверка целостности золотого образа IWE
#
# Проверяет:
#   1. qemu-img info: формат, размер, backing file, снапшоты
#   2. sha256sum: совпадение с .sha256 файлом
#   3. guestfish: ОС, установленные пакеты, пользователь iwe, SSH-ключ
#   4. (--full) Запуск VM, ожидание SSH, проверка версий
#
# Использование:
#   bash scripts/vm/verify-golden.sh --image iwe-golden-0.25.1.qcow2
#   bash scripts/vm/verify-golden.sh --image iwe-golden-0.25.1.qcow2 --full
#   bash scripts/vm/verify-golden.sh --image iwe-golden-0.25.1.qcow2 --quick
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE_PATH=""
MODE="quick"

# === Parse args ===
while [ $# -gt 0 ]; do
  case "$1" in
    --image) IMAGE_PATH="$2"; shift 2 ;;
    --image=*) IMAGE_PATH="${1#*=}"; shift ;;
    --full) MODE="full"; shift ;;
    --quick) MODE="quick"; shift ;;
    --help|-h)
      echo "Usage: verify-golden.sh --image <path> [--quick|--full]"
      echo "  --quick   Guestfish inspection only (default)"
      echo "  --full    Boot VM + SSH version check"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [ -z "$IMAGE_PATH" ]; then
  echo "ERROR: --image required" >&2
  exit 1
fi

if [ ! -f "$IMAGE_PATH" ]; then
  echo "ERROR: image not found: $IMAGE_PATH" >&2
  exit 1
fi

PASS=0
FAIL=0
_ok()   { echo "   [OK] $1"; PASS=$((PASS + 1)); }
_fail() { echo "   [FAIL] $1"; FAIL=$((FAIL + 1)); }
_skip() { echo "   [SKIP] $1"; }

echo "========================================="
echo " IWE Golden Image Verification"
echo "========================================="
echo "  Image: $IMAGE_PATH"
echo "  Mode:  $MODE"
echo ""

# =========================================================================
# 1. qemu-img info
# =========================================================================
echo "--- 1. qemu-img info ---"

command -v qemu-img >/dev/null 2>&1 || { _fail "qemu-img not found"; exit 1; }

QEMU_INFO=$(qemu-img info --output=json "$IMAGE_PATH" 2>/dev/null || echo "{}")

FMT=$(echo "$QEMU_INFO" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('format','?'))" 2>/dev/null || echo "?")
[ "$FMT" = "qcow2" ] && _ok "format: qcow2" || _fail "format: $FMT (expected qcow2)"

VSIZE=$(echo "$QEMU_INFO" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('virtual-size',0))" 2>/dev/null || echo "0")
VSIZE_GB=$(( VSIZE / 1073741824 ))
[ "$VSIZE_GB" -ge 18 ] && _ok "virtual size: ${VSIZE_GB}G" || _fail "virtual size: ${VSIZE_GB}G (expected >=18G)"

BACKING=$(echo "$QEMU_INFO" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('full-backing-filename','none'))" 2>/dev/null || echo "none")
if [ "$BACKING" != "none" ] && [ -n "$BACKING" ]; then
  _ok "backing file: $(basename "$BACKING")"
else
  _fail "backing file: missing (image should be copy-on-write)"
fi

SNAP_COUNT=$(qemu-img snapshot -l "$IMAGE_PATH" 2>/dev/null | tail -n +3 | wc -l)
[ "$SNAP_COUNT" -ge 1 ] && _ok "snapshots: $SNAP_COUNT" || _fail "snapshots: 0 (expected 'provisioned')"

echo ""

# =========================================================================
# 2. sha256sum
# =========================================================================
echo "--- 2. Checksum ---"

SHA256_FILE="${IMAGE_PATH}.sha256"
if [ -f "$SHA256_FILE" ]; then
  EXPECTED=$(cut -d' ' -f1 "$SHA256_FILE")
  ACTUAL=$(sha256sum "$IMAGE_PATH" | cut -d' ' -f1)
  if [ "$EXPECTED" = "$ACTUAL" ]; then
    _ok "sha256: ${ACTUAL:0:16}..."
  else
    _fail "sha256: MISMATCH"
    echo "       expected: ${EXPECTED:0:16}..."
    echo "       actual:   ${ACTUAL:0:16}..."
  fi
else
  _fail "sha256: file not found ($SHA256_FILE)"
fi

echo ""

# =========================================================================
# 3. guestfish inspection
# =========================================================================
echo "--- 3. Guestfish Inspection ---"

command -v guestfish >/dev/null 2>&1 || { _fail "guestfish not found (install libguestfs-tools)"; exit 1; }

GUEST_ROOT=$(guestfish --ro -a "$IMAGE_PATH" -i <<'GUESTFISH' 2>/dev/null
cat /etc/os-release
GUESTFISH
) || true
echo "$GUEST_ROOT" | grep -i "ubuntu 24" >/dev/null 2>&1 && _ok "OS: Ubuntu 24.04" || _fail "OS: not Ubuntu 24.04 or read failed"

# Check key packages
PKG_LIST=$(guestfish --ro -a "$IMAGE_PATH" -i <<'GUESTFISH' 2>/dev/null
sh "dpkg --list 2>/dev/null"
GUESTFISH
) || true

for pkg in git gh ruby expect jq shellcheck vim mc tmux curl build-essential python3 python3-yaml neovim nodejs; do
  echo "$PKG_LIST" | grep "^ii  $pkg " >/dev/null 2>&1 \
    && _ok "pkg: $pkg" || _fail "pkg: $pkg missing"
done

# Check user iwe
USER_CHECK=$(guestfish --ro -a "$IMAGE_PATH" -i <<'GUESTFISH' 2>/dev/null
sh "id iwe 2>/dev/null || echo NO_USER"
GUESTFISH
) || true
echo "$USER_CHECK" | grep -v "NO_USER" | grep "iwe" >/dev/null 2>&1 \
  && _ok "user: iwe exists" || _fail "user: iwe missing"

# Check SSH authorized_keys
SSH_CHECK=$(guestfish --ro -a "$IMAGE_PATH" -i <<'GUESTFISH' 2>/dev/null
sh "head -1 /home/iwe/.ssh/authorized_keys 2>/dev/null || echo NO_SSH"
GUESTFISH
) || true
echo "$SSH_CHECK" | grep "ssh-ed25519" >/dev/null 2>&1 \
  && _ok "ssh: authorized_keys present" || _fail "ssh: authorized_keys missing"

# Check firstboot script
FB_CHECK=$(guestfish --ro -a "$IMAGE_PATH" -i <<'GUESTFISH' 2>/dev/null
exists /home/iwe/packages-firstboot.sh
GUESTFISH
) || true
echo "$FB_CHECK" | grep "true" >/dev/null 2>&1 \
  && _ok "firstboot: script present" || _fail "firstboot: script missing"

echo ""

# =========================================================================
# 4. Full mode: boot VM + SSH check (optional)
# =========================================================================
if [ "$MODE" = "full" ]; then
  echo "--- 4. Full Boot Verification ---"

  SSH_KEY="$HOME/.ssh/id_ed25519_iwe_test"
  TEST_IMAGE="/tmp/iwe-verify-$$.qcow2"
  QEMU_PIDFILE="/tmp/iwe-verify-qemu-$$.pid"

  cleanup_vm() {
    local pid=""
    if [ -f "$QEMU_PIDFILE" ]; then
      pid=$(cat "$QEMU_PIDFILE" 2>/dev/null || echo "")
    fi
    [ -z "$pid" ] && pid=$(pgrep -f "qemu-system.*$TEST_IMAGE" 2>/dev/null || echo "")
    [ -n "$pid" ] && { kill "$pid" 2>/dev/null || true; sleep 1; kill -9 "$pid" 2>/dev/null || true; }
    rm -f "$QEMU_PIDFILE" "$TEST_IMAGE"
  }
  trap cleanup_vm EXIT

  echo "   Creating ephemeral VM..."
  qemu-img create -f qcow2 -b "$IMAGE_PATH" -F qcow2 "$TEST_IMAGE" 20G >/dev/null 2>&1
  _ok "ephemeral: created"

  echo "   Booting VM..."
  # Find free port
  PORT=2222
  while ss -tlnp 2>/dev/null | grep -q ":$PORT "; do PORT=$((PORT + 1)); [ "$PORT" -gt 2232 ] && PORT=2222; done

  qemu-system-x86_64 -enable-kvm -m 4096 -smp 2 \
    -drive file="$TEST_IMAGE",if=virtio \
    -netdev user,id=net0,hostfwd=tcp::${PORT}-:22 \
    -device virtio-net,netdev=net0 \
    -pidfile "$QEMU_PIDFILE" \
    -display none -daemonize 2>/dev/null

  echo "   Waiting for SSH (port $PORT)..."
  SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=3"
  SSH_READY=false
  for i in $(seq 1 30); do
    if ssh -p "$PORT" $SSH_OPTS iwe@localhost "echo ok" 2>/dev/null | grep -q ok; then
      SSH_READY=true
      break
    fi
    sleep 2
  done

  if $SSH_READY; then
    _ok "ssh: ready"

    # Version checks
    GIT_VER=$(ssh -p "$PORT" $SSH_OPTS iwe@localhost "git --version" 2>/dev/null || echo "")
    [ -n "$GIT_VER" ] && _ok "git: $GIT_VER" || _fail "git: missing"

    NODE_VER=$(ssh -p "$PORT" $SSH_OPTS iwe@localhost "node --version" 2>/dev/null || echo "")
    [ -n "$NODE_VER" ] && _ok "node: $NODE_VER" || _fail "node: missing"

    NPM_VER=$(ssh -p "$PORT" $SSH_OPTS iwe@localhost "npm --version" 2>/dev/null || echo "")
    [ -n "$NPM_VER" ] && _ok "npm: $NPM_VER" || _fail "npm: missing"

    # Check repo
    REPO_CHECK=$(ssh -p "$PORT" $SSH_OPTS iwe@localhost "ls ~/IWE/FMT-exocortex-template 2>/dev/null && echo FOUND || echo MISSING" 2>/dev/null)
    echo "$REPO_CHECK" | grep -q "FOUND" 2>/dev/null \
      && _ok "repo: FMT-exocortex-template present" || _ok "repo: not yet (firstboot may not have run)"
  else
    _fail "ssh: timeout"
  fi

  cleanup_vm
  trap - EXIT
fi

# =========================================================================
# Report
# =========================================================================
echo ""
echo "========================================="
echo " Verification Complete"
echo "========================================="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "  FAILURES DETECTED"
  exit 1
else
  echo "  All checks passed"
  exit 0
fi
