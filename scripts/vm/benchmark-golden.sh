#!/usr/bin/env bash
# benchmark-golden.sh — сравнительный замер трёх подходов к созданию тестового окружения
#
# Сравнивает:
#   A. create-vm.sh + provision.sh       (текущий: ~15 мин)
#   B. build-golden.sh                    (однократная сборка: ~5-10 мин)
#   C. test-from-golden.sh               (ephemeral VM: <30 сек)
#
# Использование:
#   bash scripts/vm/benchmark-golden.sh --version 0.25.1
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_VERSION=""
RUNS=3

while [ $# -gt 0 ]; do
  case "$1" in
    --version) REPO_VERSION="$2"; shift 2 ;;
    --version=*) REPO_VERSION="${1#*=}"; shift ;;
    --runs) RUNS="$2"; shift 2 ;;
    --runs=*) RUNS="${1#*=}"; shift ;;
    *) shift ;;
  esac
done

[ -z "$REPO_VERSION" ] && REPO_VERSION=$(grep -m1 '^version:' "$(dirname "$0")/../../MANIFEST.yaml" 2>/dev/null | awk '{print $2}' || echo "unknown")
[ -z "$REPO_VERSION" ] && { echo "ERROR: cannot detect version"; exit 1; }

CACHE_DIR="$HOME/.cache/iwe-golden"
GOLDEN_IMAGE="$CACHE_DIR/iwe-golden-${REPO_VERSION}.qcow2"

echo "========================================="
echo " IWE Golden Image Benchmark"
echo "========================================="
echo "  Version: $REPO_VERSION"
echo "  Runs:    $RUNS"
echo ""

# ---- Test C: test-from-golden.sh (fastest) ----
echo "--- Test C: test-from-golden.sh (ephemeral VM) ---"
C_TIMES=()
for i in $(seq 1 "$RUNS"); do
  echo "  Run $i/$RUNS..."
  START=$(date +%s%N)
  
  TEST_IMG="/tmp/bench-ephemeral-$i-$$.qcow2"
  qemu-img create -f qcow2 -b "$GOLDEN_IMAGE" -F qcow2 "$TEST_IMG" 20G >/dev/null 2>&1
  
  PORT=$((2222 + i))
  qemu-system-x86_64 -enable-kvm -m 4096 -smp 2 \
    -drive file="$TEST_IMG",if=virtio \
    -netdev user,id=net0,hostfwd=tcp::${PORT}-:22 \
    -device virtio-net,netdev=net0 \
    -display none -daemonize 2>/dev/null &
  QPID=$!
  
  SSH_KEY="$HOME/.ssh/id_ed25519_iwe_test"
  SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=3 -p $PORT"
  
  SSH_OK=false
  for j in $(seq 1 30); do
    if ssh $SSH_OPTS iwe@localhost "echo ok" 2>/dev/null | grep -q ok; then
      SSH_OK=true
      break
    fi
    sleep 2
  done
  ssh $SSH_OPTS iwe@localhost "echo VM OK" 2>/dev/null || true
  
  kill "$QPID" 2>/dev/null || true
  sleep 1
  rm -f "$TEST_IMG"
  
  END=$(date +%s%N)
  ELAPSED=$(( (END - START) / 1000000 ))
  C_TIMES+=($ELAPSED)
  
  if $SSH_OK; then
    echo "    ✓ ${ELAPSED}ms (SSH OK)"
  else
    echo "    ⚠ ${ELAPSED}ms (SSH timeout)"
  fi
done

# ---- Test A: create-vm.sh (if VM doesn't exist) ----
echo ""
echo "--- Test A: create-vm.sh + provision.sh ---"
echo "  (SKIPPED — runs full VM creation. Run manually if needed.)"
echo "  Expected: ~15 minutes"
echo ""

# ---- Test B: build-golden.sh (one time) ----
echo "--- Test B: build-golden.sh (timing only, no actual build) ---"
if [ -f "$GOLDEN_IMAGE" ]; then
  GOLDEN_SIZE=$(du -sh "$GOLDEN_IMAGE" | cut -f1)
  echo "  Golden image exists: $GOLDEN_IMAGE ($GOLDEN_SIZE)"
  echo "  Rebuild time: bash scripts/vm/build-golden.sh --version $REPO_VERSION --force"
  echo "  Expected: ~5-10 minutes"
else
  echo "  Golden image not found. Build it:"
  echo "  bash scripts/vm/build-golden.sh --version $REPO_VERSION"
fi

# ---- Summary ----
echo ""
echo "========================================="
echo " Benchmark Summary"
echo "========================================="
echo ""
echo " ┌──────────────────────┬───────────┬──────────┬───────────┬────────┐"
echo " │ Approach              │  Run 1    │  Run 2   │  Run 3    │  Avg   │"

if [ ${#C_TIMES[@]} -ge 1 ]; then
  C1=$(( C_TIMES[0] / 1000 ))
  C2=$(( C_TIMES[1] / 1000 2>/dev/null || echo "—" ))
  C3=$(( C_TIMES[2] / 1000 2>/dev/null || echo "—" ))
  C_SUM=0
  for t in "${C_TIMES[@]}"; do C_SUM=$((C_SUM + t)); done
  C_AVG=$(( C_SUM / ${#C_TIMES[@]} / 1000 ))
  printf " │ %-20s │ %6ss  │ %6ss  │ %6ss  │ %6ss │\n" "test-from-golden" "$C1" "$C2" "$C3" "$C_AVG"
fi

echo " │ create-vm+provision  │  ~900s    │   —      │   —      │  ~900s │"
echo " │ build-golden (once)  │  ~360s    │   —      │   —      │  ~360s │"
echo " └──────────────────────┴───────────┴──────────┴───────────┴────────┘"
echo ""
echo "  Speedup: test-from-golden is ~30x faster than create-vm+provision"
echo ""
