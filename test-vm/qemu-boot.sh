#!/usr/bin/env bash
# LogOS Gentoo — QEMU Boot Automation
# Boots the test qcow2 disk in a full QEMU/KVM VM for manual or automated testing
#
# Usage:
#   ./qemu-boot.sh              # Interactive boot (console + VGA)
#   ./qemu-boot.sh --headless   # Headless with serial console
#   ./qemu-boot.sh --install    # Boot from Gentoo ISO for initial install
#
# Requirements: qemu-system-x86_64, OVMF (UEFI firmware)
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QCOW2="${TEST_DIR}/logos-test.qcow2"
ISO="${TEST_DIR}/gentoo-minimal.iso"
OVMF="/usr/share/OVMF/OVMF_CODE.fd"
OVMF_VARS="/usr/share/OVMF/OVMF_VARS.fd"
MODE="${1:-interactive}"

# VM resources
MEMORY="8G"
CPUS="4"
SSH_PORT="2222"

die() { echo "ERROR: $*" >&2; exit 1; }

[[ -f "${QCOW2}" ]] || die "Test disk not found: ${QCOW2}"
[[ -f "${OVMF}" ]]  || die "OVMF not found: ${OVMF} (install ovmf package)"

# Create per-VM OVMF_VARS copy (UEFI variable store is per-machine)
VARS_COPY="${TEST_DIR}/OVMF_VARS_logos.fd"
if [[ ! -f "${VARS_COPY}" ]]; then
  if [[ -f "${OVMF_VARS}" ]]; then
    cp "${OVMF_VARS}" "${VARS_COPY}"
  else
    # Create empty vars file if template doesn't exist
    truncate -s 256K "${VARS_COPY}"
  fi
fi

COMMON_ARGS=(
  -enable-kvm
  -cpu host
  -m "${MEMORY}"
  -smp "${CPUS}"
  -drive "if=pflash,format=raw,readonly=on,file=${OVMF}"
  -drive "if=pflash,format=raw,file=${VARS_COPY}"
  -drive "file=${QCOW2},format=qcow2,if=virtio"
  -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22"
  -device "virtio-net-pci,netdev=net0"
  -device "virtio-rng-pci"
)

case "${MODE}" in
  --install)
    [[ -f "${ISO}" ]] || die "Gentoo ISO not found: ${ISO} (download first)"
    echo "== Booting from Gentoo ISO for installation =="
    echo "   Disk: ${QCOW2}"
    echo "   ISO:  ${ISO}"
    echo "   SSH:  ssh -p ${SSH_PORT} root@localhost"
    echo ""
    qemu-system-x86_64 \
      "${COMMON_ARGS[@]}" \
      -cdrom "${ISO}" \
      -boot d \
      -vga virtio \
      -display gtk
    ;;

  --headless)
    echo "== Headless boot with serial console =="
    echo "   Disk: ${QCOW2}"
    echo "   SSH:  ssh -p ${SSH_PORT} root@localhost"
    echo "   Serial console active. Press Ctrl-A X to exit."
    echo ""
    qemu-system-x86_64 \
      "${COMMON_ARGS[@]}" \
      -nographic \
      -serial mon:stdio \
      -append "console=ttyS0,115200"
    ;;

  --interactive|interactive)
    echo "== Interactive boot (GTK display) =="
    echo "   Disk: ${QCOW2}"
    echo "   SSH:  ssh -p ${SSH_PORT} root@localhost"
    echo ""
    qemu-system-x86_64 \
      "${COMMON_ARGS[@]}" \
      -vga virtio \
      -display gtk \
      -device "usb-ehci" \
      -device "usb-tablet"
    ;;

  *)
    echo "Usage: $0 [--interactive|--headless|--install]"
    exit 1
    ;;
esac
