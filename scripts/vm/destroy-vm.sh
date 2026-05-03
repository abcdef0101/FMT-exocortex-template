#!/usr/bin/env bash
# destroy-vm.sh — удаление тестовой VM
set -euo pipefail

VM_NAME="iwe-test"
VM_DIR="$HOME/.iwe-test-vm"

echo "========================================="
echo " IWE Test VM — Destroy"
echo "========================================="

if ! virsh list --name --all 2>/dev/null | grep -q "^${VM_NAME}$"; then
  echo "  VM '$VM_NAME' not found."
  echo "  Disk and secrets preserved: $VM_DIR"
  exit 0
fi

echo "  Destroying VM: $VM_NAME"
virsh destroy "$VM_NAME" 2>/dev/null || true
virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true

echo ""
echo "VM removed. To clean up disk and secrets:"
echo "  rm -rf $VM_DIR"
