#!/usr/bin/env bash
# lib/detect.sh — LogOS hardware detection functions
# Sourced by scripts that need CPU, GPU, disk, or UUID detection.
# Requires lib/common.sh to be sourced first.

# ── CPU detection ───────────────────────────────────────────────────
# Returns "intel", "amd", or "unknown".
detect_cpu_vendor() {
  if grep -q "GenuineIntel" /proc/cpuinfo 2>/dev/null; then
    echo "intel"
  elif grep -q "AuthenticAMD" /proc/cpuinfo 2>/dev/null; then
    echo "amd"
  else
    echo "unknown"
  fi
}

# ── GPU detection ───────────────────────────────────────────────────
# Prints one or more of: "nvidia", "amd", "intel".
# Prints "none" if no discrete/integrated GPU is found.
# Ported from phase3-desktop.sh:17-29.
detect_gpu() {
  local found=0

  if ! command -v lspci >/dev/null 2>&1; then
    log_warn "lspci not found — install pciutils for GPU detection"
    echo "none"
    return
  fi

  local pci_output
  pci_output="$(lspci 2>/dev/null)"

  if echo "${pci_output}" | grep -qi "nvidia"; then
    echo "nvidia"
    found=1
  fi
  if echo "${pci_output}" | grep -qi "amd.*vga\|radeon"; then
    echo "amd"
    found=1
  fi
  if echo "${pci_output}" | grep -qi "intel.*vga\|intel.*graphics"; then
    echo "intel"
    found=1
  fi

  if [[ "${found}" -eq 0 ]]; then
    echo "none"
  fi
}

# ── Disk detection ──────────────────────────────────────────────────
# Lists available block devices, filtering out loop, rom, and ram devices.
detect_disks() {
  lsblk -dnpo NAME,TYPE,SIZE,MODEL 2>/dev/null \
    | grep -E '^\S+\s+disk' \
    | awk '{print $1, $3, $4}'
}

# ── UEFI detection ──────────────────────────────────────────────────
# Returns 0 if booted in UEFI mode, 1 if legacy BIOS.
is_uefi() {
  [[ -d /sys/firmware/efi/efivars ]]
}

# ── LUKS UUID detection ────────────────────────────────────────────
# Ported from phase2-transform.sh:24-33.
# Respects LOGOS_CRYPT_UUID_OVERRIDE from logos.conf.
detect_crypt_uuid() {
  if [[ -n "${LOGOS_CRYPT_UUID_OVERRIDE:-}" ]]; then
    echo "${LOGOS_CRYPT_UUID_OVERRIDE}"
    return
  fi

  local crypt_dev
  crypt_dev="$(blkid -t TYPE=crypto_LUKS -o device 2>/dev/null | head -n1 || true)"
  if [[ -z "${crypt_dev}" ]]; then
    log_err "Unable to locate crypto_LUKS device."
    log_err "Set LOGOS_CRYPT_UUID_OVERRIDE in logos.conf."
    return 1
  fi

  blkid -s UUID -o value "${crypt_dev}"
}

# ── Btrfs UUID detection ───────────────────────────────────────────
# Ported from phase2-transform.sh:35-52.
# Respects LOGOS_BTRFS_UUID_OVERRIDE from logos.conf.
detect_btrfs_uuid() {
  if [[ -n "${LOGOS_BTRFS_UUID_OVERRIDE:-}" ]]; then
    echo "${LOGOS_BTRFS_UUID_OVERRIDE}"
    return
  fi

  # Try the mounted root first
  local root_dev uuid
  root_dev="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
  if [[ -n "${root_dev}" ]]; then
    uuid="$(blkid -s UUID -o value "${root_dev}" 2>/dev/null || true)"
    if [[ -n "${uuid}" ]]; then
      echo "${uuid}"
      return
    fi
  fi

  # Fallback: probe for any btrfs device
  local btrfs_dev
  btrfs_dev="$(blkid -t TYPE=btrfs -o device 2>/dev/null | head -n1 || true)"
  if [[ -z "${btrfs_dev}" ]]; then
    log_err "Unable to locate btrfs UUID."
    log_err "Set LOGOS_BTRFS_UUID_OVERRIDE in logos.conf."
    return 1
  fi

  blkid -s UUID -o value "${btrfs_dev}"
}
