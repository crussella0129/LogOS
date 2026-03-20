#!/usr/bin/env bash
# 01-disk-setup.sh — Partitioning + Encryption + Btrfs Subvolumes
# Context: Run from the Artix Linux live USB, after 00-verify-env.sh.
# DESTRUCTIVE: Wipes the target disk. Requires explicit confirmation.
#
# Ported from: Master spec sections 6.3-6.8 (partition scheme, subvol layout)

LOGOS_SECTION="01-disk"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/detect.sh"

require_root
require_live_env
load_config "${SCRIPT_DIR}/../logos.conf"
set_partition_vars

# ── Safety gate ─────────────────────────────────────────────────────
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║  ⚠  DESTRUCTIVE OPERATION                               ║"
echo "║                                                           ║"
echo "║  Target disk: ${LOGOS_DISK}"
echo "║  ALL DATA ON THIS DISK WILL BE DESTROYED.                ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

if ! lsblk "${LOGOS_DISK}" 2>/dev/null; then
  log_err "Disk ${LOGOS_DISK} not found. Check LOGOS_DISK in logos.conf."
  exit 1
fi

confirm "Destroy all data on ${LOGOS_DISK} and create LogOS partitions?"

# ── Partitioning via sgdisk ─────────────────────────────────────────
log "Creating GPT partition table on ${LOGOS_DISK}"
sgdisk --zap-all "${LOGOS_DISK}"

log "Creating EFI partition (${LOGOS_EFI_SIZE:-1G})"
sgdisk -n "1:0:+${LOGOS_EFI_SIZE:-1G}" -t 1:EF00 -c 1:"EFI" "${LOGOS_DISK}"

log "Creating boot partition (${LOGOS_BOOT_SIZE:-4G})"
sgdisk -n "2:0:+${LOGOS_BOOT_SIZE:-4G}" -t 2:8300 -c 2:"BOOT" "${LOGOS_DISK}"

log "Creating root partition (remainder)"
sgdisk -n 3:0:0 -t 3:8309 -c 3:"ROOT" "${LOGOS_DISK}"

# Re-read partition table
partprobe "${LOGOS_DISK}" 2>/dev/null || sleep 2
log_ok "Partitions created"

# ── LUKS encryption ─────────────────────────────────────────────────
if [[ "${LOGOS_ENCRYPT:-1}" == "1" ]]; then
  log "Formatting ${ROOT_PART} with LUKS2 (${LOGOS_LUKS_PBKDF:-argon2id})"
  cryptsetup luksFormat --type luks2 \
    --cipher "${LOGOS_LUKS_CIPHER:-aes-xts-plain64}" \
    --key-size "${LOGOS_LUKS_KEY_SIZE:-512}" \
    --hash "${LOGOS_LUKS_HASH:-sha512}" \
    --pbkdf "${LOGOS_LUKS_PBKDF:-argon2id}" \
    "${ROOT_PART}"

  log "Opening LUKS container"
  cryptsetup open "${ROOT_PART}" cryptroot
  BTRFS_DEV="/dev/mapper/cryptroot"
  log_ok "LUKS2 encryption configured"
else
  log_warn "Encryption DISABLED — not recommended for production use"
  BTRFS_DEV="${ROOT_PART}"
fi

# ── Filesystem formatting ──────────────────────────────────────────
log "Formatting EFI partition (FAT32)"
mkfs.fat -F32 -n EFI "${EFI_PART}"

log "Formatting boot partition (ext4)"
mkfs.ext4 -L BOOT "${BOOT_PART}"

log "Formatting root partition (Btrfs)"
mkfs.btrfs -f -L ROOT "${BTRFS_DEV}"

log_ok "Filesystems created"

# ── Btrfs subvolumes ───────────────────────────────────────────────
log "Creating Btrfs subvolumes"
mount "${BTRFS_DEV}" /mnt

btrfs subvolume create /mnt/@           # Root filesystem
btrfs subvolume create /mnt/@home       # User data
btrfs subvolume create /mnt/@canon      # Cold Canon (archival, copies=2)
btrfs subvolume create /mnt/@mesh       # Warm Mesh (sync workspace)
btrfs subvolume create /mnt/@snapshots  # Snapper snapshots
btrfs subvolume create /mnt/@log        # Logs (nodatacow for performance)
btrfs subvolume create /mnt/@pkg        # Package cache

btrfs subvolume list /mnt
umount /mnt

log_ok "7 subvolumes created"

# ── Mount all filesystems ──────────────────────────────────────────
BTRFS_OPTS="${LOGOS_BTRFS_OPTS:-noatime,compress=zstd:3,space_cache=v2,discard=async}"

log "Mounting subvolumes at /mnt"
mount -o "subvol=@,${BTRFS_OPTS}" "${BTRFS_DEV}" /mnt

mkdir -p /mnt/{boot,home,.snapshots,var/log,var/cache/pacman/pkg,srv/cold-canon,srv/warm-mesh}
mkdir -p /mnt/boot/efi

mount -o "subvol=@home,${BTRFS_OPTS}"      "${BTRFS_DEV}" /mnt/home
mount -o "subvol=@snapshots,${BTRFS_OPTS}"  "${BTRFS_DEV}" /mnt/.snapshots
# nodatacow is incompatible with compress — build @log opts independently
mount -o "subvol=@log,noatime,space_cache=v2,discard=async,nodatacow" "${BTRFS_DEV}" /mnt/var/log
mount -o "subvol=@pkg,${BTRFS_OPTS}"        "${BTRFS_DEV}" /mnt/var/cache/pacman/pkg
mount -o "subvol=@canon,${BTRFS_OPTS}"      "${BTRFS_DEV}" /mnt/srv/cold-canon
mount -o "subvol=@mesh,${BTRFS_OPTS}"       "${BTRFS_DEV}" /mnt/srv/warm-mesh

mount "${BOOT_PART}" /mnt/boot
mount "${EFI_PART}" /mnt/boot/efi

log_ok "All filesystems mounted"

# ── Verification ───────────────────────────────────────────────────
echo ""
log "Mount verification:"
findmnt -t btrfs,vfat,ext4 --target /mnt -R
echo ""

log_ok "Disk setup complete. Proceed to 02-base-install.sh"
