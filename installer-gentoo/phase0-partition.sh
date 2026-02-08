#!/usr/bin/env bash
# LogOS Gentoo — Phase 0: Disk Partitioning
# LUKS2 + Argon2id encryption, Btrfs with 6 subvolumes
#
# Usage: DISK=/dev/sdX ./phase0-partition.sh
#   or:  ./phase0-partition.sh /dev/sdX
#
# WARNING: This will DESTROY all data on the target disk.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

require_root
require_cmds sgdisk mkfs.fat mkfs.ext4 mkfs.btrfs cryptsetup

DISK="${1:-${DISK:-}}"
if [[ -z "${DISK}" ]]; then
  die "Usage: DISK=/dev/sdX $0  or  $0 /dev/sdX"
fi

if [[ ! -b "${DISK}" ]]; then
  die "Not a block device: ${DISK}"
fi

# Safety check
echo ""
echo "${RED}WARNING: This will DESTROY ALL DATA on ${DISK}${RESET}"
echo ""
lsblk "${DISK}"
echo ""
confirm "Are you absolutely sure?" || die "Aborted."

# ── Partition Layout ──────────────────────────────────────────────
# 1: EFI System Partition  (1 GB, FAT32)
# 2: Boot partition         (4 GB, ext4) — unencrypted for GRUB
# 3: Root partition          (remainder) — LUKS2 → Btrfs
# ──────────────────────────────────────────────────────────────────

log "Wiping partition table on ${DISK}"
sgdisk --zap-all "${DISK}"

log "Creating partitions"
sgdisk --new=1:0:+1G   --typecode=1:ef00 --change-name=1:"EFI"  "${DISK}"
sgdisk --new=2:0:+4G   --typecode=2:8300 --change-name=2:"Boot" "${DISK}"
sgdisk --new=3:0:0     --typecode=3:8309 --change-name=3:"Root" "${DISK}"

# Determine partition device names (handle NVMe /dev/nvme0n1p1 vs /dev/sda1)
if [[ "${DISK}" == *nvme* ]] || [[ "${DISK}" == *mmcblk* ]]; then
  PART_EFI="${DISK}p1"
  PART_BOOT="${DISK}p2"
  PART_ROOT="${DISK}p3"
else
  PART_EFI="${DISK}1"
  PART_BOOT="${DISK}2"
  PART_ROOT="${DISK}3"
fi

# Wait for kernel to recognize new partitions
partprobe "${DISK}" 2>/dev/null || true
sleep 2

log "Formatting EFI partition (FAT32)"
mkfs.fat -F32 -n EFI "${PART_EFI}"

log "Formatting boot partition (ext4)"
mkfs.ext4 -L boot "${PART_BOOT}"

# ── LUKS2 Encryption ─────────────────────────────────────────────
log "Setting up LUKS2 encryption on ${PART_ROOT}"
echo ""
echo "You will be prompted to set the disk encryption passphrase."
echo "Choose a strong passphrase — this protects all data at rest."
echo ""

cryptsetup luksFormat \
  --type luks2 \
  --cipher aes-xts-plain64 \
  --key-size 512 \
  --hash sha512 \
  --pbkdf argon2id \
  --iter-time 5000 \
  --verify-passphrase \
  "${PART_ROOT}"

log "Opening LUKS volume"
cryptsetup open "${PART_ROOT}" cryptroot

# ── Btrfs + Subvolumes ───────────────────────────────────────────
log "Creating Btrfs filesystem on /dev/mapper/cryptroot"
mkfs.btrfs -L LogOS /dev/mapper/cryptroot

log "Mounting and creating subvolumes"
mount /dev/mapper/cryptroot /mnt

BTRFS_OPTS="noatime,compress=zstd:3,space_cache=v2,discard=async"

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@canon
btrfs subvolume create /mnt/@mesh
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@log

# Set copies=2 on canon subvolume for bitrot protection
btrfs property set /mnt/@canon compression zstd:3

umount /mnt

# ── Mount Hierarchy ──────────────────────────────────────────────
log "Mounting subvolumes"
mount -o "subvol=@,${BTRFS_OPTS}" /dev/mapper/cryptroot /mnt

mkdir -p /mnt/{home,srv/cold-canon,srv/warm-mesh,var/log,.snapshots,boot,boot/efi}

mount -o "subvol=@home,${BTRFS_OPTS}"     /dev/mapper/cryptroot /mnt/home
mount -o "subvol=@canon,${BTRFS_OPTS}"    /dev/mapper/cryptroot /mnt/srv/cold-canon
mount -o "subvol=@mesh,${BTRFS_OPTS}"     /dev/mapper/cryptroot /mnt/srv/warm-mesh
mount -o "subvol=@snapshots,${BTRFS_OPTS}" /dev/mapper/cryptroot /mnt/.snapshots
mount -o "subvol=@log,nodatacow,${BTRFS_OPTS}" /dev/mapper/cryptroot /mnt/var/log

mount "${PART_BOOT}" /mnt/boot
mount "${PART_EFI}"  /mnt/boot/efi

# ── Save UUIDs ────────────────────────────────────────────────────
CRYPT_UUID="$(blkid -s UUID -o value "${PART_ROOT}")"
BTRFS_UUID="$(blkid -s UUID -o value /dev/mapper/cryptroot)"
BOOT_UUID="$(blkid -s UUID -o value "${PART_BOOT}")"
EFI_UUID="$(blkid -s UUID -o value "${PART_EFI}")"

mkdir -p /mnt/tmp
cat > /mnt/tmp/logos-uuids << EOF
CRYPT_UUID="${CRYPT_UUID}"
BTRFS_UUID="${BTRFS_UUID}"
BOOT_UUID="${BOOT_UUID}"
EFI_UUID="${EFI_UUID}"
PART_ROOT="${PART_ROOT}"
EOF

log "UUIDs saved to /mnt/tmp/logos-uuids"
echo "  CRYPT_UUID = ${CRYPT_UUID}"
echo "  BTRFS_UUID = ${BTRFS_UUID}"
echo "  BOOT_UUID  = ${BOOT_UUID}"
echo "  EFI_UUID   = ${EFI_UUID}"

echo ""
log "Phase 0 complete. Disk is ready for Stage3 installation."
log "Next: ./phase1-stage3.sh"
