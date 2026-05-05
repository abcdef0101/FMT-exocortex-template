#!/usr/bin/env bash
# build-container.sh — build IWE test container image (analog of build-golden.sh for VM)
#
# Usage:
#   bash scripts/container/build-container.sh [--version 0.25.1] [--force]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CACHE_DIR="$HOME/.cache/iwe-container"

FORCE=false
REPO_VERSION=""

while [ $# -gt 0 ]; do
  case "$1" in
    --version) REPO_VERSION="$2"; shift 2 ;;
    --version=*) REPO_VERSION="${1#*=}"; shift ;;
    --force) FORCE=true; shift ;;
    --help|-h) echo "Usage: build-container.sh [--version V] [--force]"; exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

[ -z "$REPO_VERSION" ] && REPO_VERSION=$(grep -m1 '^version:' "$ROOT_DIR/MANIFEST.yaml" 2>/dev/null | awk '{print $2}')
[ -z "$REPO_VERSION" ] && { echo "ERROR: cannot detect version. Use --version." >&2; exit 1; }

IMAGE_TAG="iwe-test:${REPO_VERSION}"
CONTAINERFILE="$SCRIPT_DIR/Containerfile"
IMAGE_ID_FILE="$CACHE_DIR/iwe-test-${REPO_VERSION}.id"

echo "========================================="
echo " IWE Container Build"
echo "========================================="
echo "  Version: $REPO_VERSION"
echo "  Tag:     $IMAGE_TAG"
echo ""

command -v podman >/dev/null 2>&1 || { echo "ERROR: podman not found" >&2; exit 1; }
[ ! -f "$CONTAINERFILE" ] && { echo "ERROR: Containerfile not found: $CONTAINERFILE" >&2; exit 1; }

EXISTING_ID=$(podman images -q "$IMAGE_TAG" 2>/dev/null || true)
if [ -n "$EXISTING_ID" ] && ! $FORCE; then
  echo "  Image exists: ${EXISTING_ID:0:12}"
  echo "  Use --force to rebuild."
  exit 0
fi

mkdir -p "$CACHE_DIR"

echo "--- Building image ---"
BUILD_LOG="$CACHE_DIR/build-${REPO_VERSION}-$$.log"

if ! podman build -t "$IMAGE_TAG" -f "$CONTAINERFILE" "$ROOT_DIR" >"$BUILD_LOG" 2>&1; then
  echo "  ✗ Build FAILED"
  tail -20 "$BUILD_LOG" | sed 's/^/  | /'
  exit 1
fi

IMAGE_ID=$(podman images -q "$IMAGE_TAG" 2>/dev/null)
echo "$IMAGE_ID" > "$IMAGE_ID_FILE"
echo "  ✓ Image built: ${IMAGE_ID:0:12}"

echo ""
echo "========================================="
echo " ✓ Container Image Built"
echo "========================================="
echo "  Tag:   $IMAGE_TAG"
echo "  ID:    ${IMAGE_ID:0:12}"
echo "  Size:  $(podman image inspect "$IMAGE_TAG" --format '{{.Size}}' 2>/dev/null | python3 -c "import sys; s=int(sys.stdin.read().strip()); print(f'{s//1073741824}G')" 2>/dev/null || echo '?')"
echo ""
echo "  Verify: bash scripts/container/verify-container.sh --version $REPO_VERSION"
echo "  Test:   bash scripts/container/test-from-container.sh --version $REPO_VERSION"
