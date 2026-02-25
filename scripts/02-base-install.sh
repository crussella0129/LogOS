#!/usr/bin/env bash
# 02-base-install.sh — pacstrap + fstab generation
# Context: Run from the Arch Linux live USB, after 01-disk-setup.sh.
# Installs Tier 0 (boot-critical) and Tier 1 (security) packages,
# generates fstab, and copies LogOS config into the new system.
#
# Ported from: Master spec sections 7-8 (tier packages)

LOGOS_SECTION="02-base"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/detect.sh"

require_root
require_live_env
load_config "${SCRIPT_DIR}/../logos.conf"

# ── Verify mounts ──────────────────────────────────────────────────
if ! mountpoint -q /mnt; then
  log_err "/mnt is not mounted. Run 01-disk-setup.sh first."
  exit 1
fi

# ── Detect CPU microcode ───────────────────────────────────────────
CPU_VENDOR="$(detect_cpu_vendor)"
UCODE_PKG=""
case "${CPU_VENDOR}" in
  intel) UCODE_PKG="intel-ucode" ;;
  amd)   UCODE_PKG="amd-ucode" ;;
  *)     log_warn "Unknown CPU vendor — skipping microcode" ;;
esac

# ── Tier 0: Boot-critical packages ─────────────────────────────────
log "Installing Tier 0 (boot-critical) packages via pacstrap"

TIER0_PKGS=(
  base linux linux-firmware linux-headers
  linux-lts linux-lts-headers
  linux-zen linux-zen-headers
  grub efibootmgr
  btrfs-progs cryptsetup
  networkmanager
  sudo nano
  man-db man-pages
)

if [[ -n "${UCODE_PKG}" ]]; then
  TIER0_PKGS+=("${UCODE_PKG}")
fi

if [[ "${LOGOS_ENABLE_HARDENED:-0}" == "1" ]]; then
  TIER0_PKGS+=(linux-hardened linux-hardened-headers)
fi

pacstrap -K /mnt "${TIER0_PKGS[@]}"
log_ok "Tier 0 installed"

# ── Tier 1: Security infrastructure ────────────────────────────────
log "Installing Tier 1 (security) packages"

TIER1_PKGS=(apparmor audit ufw openssh)

if [[ "${LOGOS_FAIL2BAN:-1}" == "1" ]]; then
  TIER1_PKGS+=(fail2ban)
fi

arch-chroot /mnt pacman -S --noconfirm --needed "${TIER1_PKGS[@]}"
log_ok "Tier 1 installed"

# ── Generate fstab ─────────────────────────────────────────────────
log "Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab

# Note: Cold Canon's copies=2 redundancy is a btrfs filesystem-level property,
# not a mount option. It is set by mkfs.btrfs --data dup or via btrfs property.
# The @canon subvol gets standard mount options; data redundancy is configured
# separately in 08-knowledge.sh via chattr +C and btrfs balance.

log_ok "fstab generated"
log "Verify fstab:"
cat /mnt/etc/fstab
echo ""

# ── Copy LogOS config into new system ──────────────────────────────
log "Copying LogOS configuration to /mnt/root/LogOS/"
mkdir -p /mnt/root/LogOS/lib
cp "${SCRIPT_DIR}/../logos.conf"        /mnt/root/LogOS/
cp "${SCRIPT_DIR}/../lib/"*.sh          /mnt/root/LogOS/lib/
cp "${SCRIPT_DIR}"/*.sh                 /mnt/root/LogOS/
chmod +x /mnt/root/LogOS/*.sh

# Copy dotfiles (themes + desktop configs + shared configs)
if [[ -d "${SCRIPT_DIR}/../dotfiles" ]]; then
  cp -r "${SCRIPT_DIR}/../dotfiles" /mnt/root/LogOS/
  log "Dotfiles copied to /mnt/root/LogOS/dotfiles/"
fi

log_ok "Base install complete. Proceed to: arch-chroot /mnt, then run 03-chroot-setup.sh"
