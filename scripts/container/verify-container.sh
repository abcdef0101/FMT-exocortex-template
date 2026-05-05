#!/usr/bin/env bash
# verify-container.sh — verify IWE test container image integrity
# Analogous to verify-golden.sh but uses podman inspect instead of qemu-img/guestfish.
#
# Usage:
#   bash scripts/container/verify-container.sh --version 0.25.1
#   bash scripts/container/verify-container.sh --version 0.25.1 --full
set -euo pipefail

REPO_VERSION=""
MODE="quick"

while [ $# -gt 0 ]; do
  case "$1" in
    --version) REPO_VERSION="$2"; shift 2 ;;
    --version=*) REPO_VERSION="${1#*=}"; shift ;;
    --full) MODE="full"; shift ;;
    --quick) MODE="quick"; shift ;;
    --help|-h)
      echo "Usage: verify-container.sh --version <V> [--quick|--full]"
      echo "  --quick   Metadata inspection only (default)"
      echo "  --full    Run container + tool version check"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

[ -z "$REPO_VERSION" ] && { echo "ERROR: --version required" >&2; exit 1; }

IMAGE_TAG="iwe-test:${REPO_VERSION}"

PASS=0
FAIL=0
_ok()   { echo "   [OK] $1"; PASS=$((PASS + 1)); }
_fail() { echo "   [FAIL] $1"; FAIL=$((FAIL + 1)); }
_skip() { echo "   [SKIP] $1"; }

echo "========================================="
echo " IWE Container Verification"
echo "========================================="
echo "  Image: $IMAGE_TAG"
echo "  Mode:  $MODE"
echo ""

command -v podman >/dev/null 2>&1 || { _fail "podman not found"; exit 1; }

# =========================================================================
# 1. Image exists
# =========================================================================
echo "--- 1. Image Metadata ---"

IMAGE_ID=$(podman images -q "$IMAGE_TAG" 2>/dev/null || true)
if [ -n "$IMAGE_ID" ]; then
  _ok "image exists: ${IMAGE_ID:0:12}"
else
  _fail "image not found: $IMAGE_TAG"
  echo "  Build it: bash scripts/container/build-container.sh --version $REPO_VERSION"
  exit 1
fi

INSPECT=$(podman image inspect "$IMAGE_TAG" 2>/dev/null | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)[0]))" 2>/dev/null || echo "{}")

OS=$(echo "$INSPECT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('Os','?'))" 2>/dev/null || echo "?")
[ "$OS" = "linux" ] && _ok "os: linux" || _fail "os: $OS"

ARCH=$(echo "$INSPECT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('Architecture','?'))" 2>/dev/null || echo "?")
[ "$ARCH" = "amd64" ] && _ok "arch: amd64" || _fail "arch: $ARCH"

SIZE_BYTES=$(echo "$INSPECT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('Size',0))" 2>/dev/null || echo "0")
SIZE_GB=$(python3 -c "print(f'{$SIZE_BYTES/1073741824:.1f}G')" 2>/dev/null || echo "?")
_ok "size: $SIZE_GB"

CREATED=$(echo "$INSPECT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('Created','?')[:19])" 2>/dev/null || echo "?")
_ok "created: $CREATED"

# Check base image
BASE_IMAGE=$(echo "$INSPECT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
layers=d.get('RootFS',{}).get('Layers',[])
print(f'{len(layers)} layers')
" 2>/dev/null || echo "?")
_ok "layers: $BASE_IMAGE"

echo ""

# =========================================================================
# 2. Quick mode: check labels/env from inspect
# =========================================================================
echo "--- 2. Image Config ---"

ENTRYPOINT=$(echo "$INSPECT" | python3 -c "import json,sys; d=json.load(sys.stdin); c=d.get('Config',{}); print(c.get('Entrypoint',['?']))" 2>/dev/null || echo "?")
echo "$ENTRYPOINT" | grep -q "sleep" && _ok "entrypoint: sleep infinity" || _fail "entrypoint: $ENTRYPOINT"

USER=$(echo "$INSPECT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('Config',{}).get('User','?'))" 2>/dev/null || echo "?")
[ "$USER" = "iwe" ] && _ok "user: iwe" || _fail "user: $USER (expected iwe)"

WORKDIR=$(echo "$INSPECT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('Config',{}).get('WorkingDir','?'))" 2>/dev/null || echo "?")
[ "$WORKDIR" = "/home/iwe" ] && _ok "workdir: /home/iwe" || _fail "workdir: $WORKDIR"

echo ""

# =========================================================================
# 3. Full mode: run container + tool checks
# =========================================================================
if [ "$MODE" = "full" ]; then
  echo "--- 3. Full Runtime Check ---"

  CONTAINER_NAME="iwe-verify-$$"

  cleanup() {
    podman rm -f "$CONTAINER_NAME" 2>/dev/null || true
  }
  trap cleanup EXIT

  podman run -d --name "$CONTAINER_NAME" "$IMAGE_TAG" >/dev/null 2>&1
  _ok "container started"

  # OS check
  OS_OUT=$(podman exec "$CONTAINER_NAME" cat /etc/os-release 2>/dev/null || echo "")
  echo "$OS_OUT" | grep -qi "ubuntu 24" && _ok "os: Ubuntu 24.04" || _fail "os: not Ubuntu 24.04"

  # User check
  podman exec "$CONTAINER_NAME" id iwe 2>/dev/null && _ok "user: iwe exists" || _fail "user: iwe missing"

  # Tool versions
  for tool in git node npm ruby python3 jq shellcheck; do
    VER=$(podman exec "$CONTAINER_NAME" bash -c "$tool --version 2>/dev/null | head -1" || echo "")
    [ -n "$VER" ] && _ok "tool: $tool ($VER)" || _fail "tool: $tool missing"
  done

  # npm global tools
  for npm_tool in opencode claude codex; do
    podman exec "$CONTAINER_NAME" bash -lc "command -v $npm_tool" >/dev/null 2>&1 \
      && _ok "npm: $npm_tool in PATH" || _fail "npm: $npm_tool not in PATH"
  done

  # PATH check
  PATH_OUT=$(podman exec "$CONTAINER_NAME" bash -lc 'echo $PATH' 2>/dev/null)
  echo "$PATH_OUT" | grep -q ".local/bin" && _ok "path: .local/bin present" || _fail "path: .local/bin missing"

  cleanup
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
