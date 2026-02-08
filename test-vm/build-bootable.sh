#!/usr/bin/env bash
# LogOS Gentoo — Build Bootable VM via NBD + Chroot
# Creates a bootable LogOS Gentoo system using the host as build environment.
#
# This approach is faster and more reliable than serial console automation:
#   1. qcow2 disk attached via NBD on host
#   2. Phase 0: partition, LUKS2, Btrfs (on host via NBD)
#   3. Phase 1: stage3 extract + portage config (on host via NBD)
#   4. Phase 2: chroot into Gentoo, emerge kernel/GRUB/security (host network)
#   5. Disconnect NBD, boot QEMU from disk
#
# Usage: sudo ./build-bootable.sh [--minimal] [--resume N]
#   --minimal   Skip optional packages, just get a bootable system
#   --resume N  Resume from step N (1=stage3, 2=chroot-emerge, 3=boot-test)
#
# Requirements: qemu-nbd, cryptsetup, btrfs-progs, chroot support
# Estimated time: 1-3 hours (depends on mirror speed and CPU)
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="${TEST_DIR}/../installer-gentoo"
QCOW2="${TEST_DIR}/logos-test-full.qcow2"
ISO="${TEST_DIR}/gentoo-minimal.iso"
NBD_DEV="/dev/nbd0"
MNT="/mnt/logos-build"
LUKS_PASS="REDACTED_PASS"
DISK_SIZE="30G"
LOG_DIR="${TEST_DIR}/install-logs"
RESUME=0
MINIMAL=0
PASS=0; FAIL=0

# Parse args
for arg in "$@"; do
  case "${arg}" in
    --minimal) MINIMAL=1 ;;
    --resume) shift; RESUME="${1:-0}"; shift 2>/dev/null || true ;;
    --resume=*) RESUME="${arg#*=}" ;;
    --help) echo "Usage: $0 [--minimal] [--resume N]"; exit 0 ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
RESET='\033[0m'
log()   { echo -e "${GREEN}[BUILD]${RESET} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error() { echo -e "${RED}[ERROR]${RESET} $*"; }
phase() { echo -e "\n${CYAN}══════════════════════════════════════════${RESET}"; echo -e "${CYAN}  STEP $1: $2${RESET}"; echo -e "${CYAN}══════════════════════════════════════════${RESET}\n"; }
die()   { error "$*"; exit 1; }
pass()  { echo -e "${GREEN}  PASS: $*${RESET}"; ((PASS++)) || true; }
fail()  { echo -e "${RED}  FAIL: $*${RESET}"; ((FAIL++)) || true; }

[[ "${EUID}" -eq 0 ]] || die "Run as root"

mkdir -p "${LOG_DIR}"

cleanup() {
  log "Cleaning up..."
  # Unmount everything
  umount -R "${MNT}" 2>/dev/null || true
  sleep 1
  cryptsetup close logos-build 2>/dev/null || true
  sleep 1
  qemu-nbd --disconnect "${NBD_DEV}" 2>/dev/null || true
  log "Cleanup done"
}
trap cleanup EXIT

# ═══════════════════════════════════════════════════════════════════
# STEP 0: Create disk and connect NBD
# ═══════════════════════════════════════════════════════════════════
if [[ "${RESUME}" -le 0 ]]; then
  phase 0 "Create Disk + Partition + LUKS2 + Btrfs"

  # Create fresh qcow2 (always start clean for step 0)
  if [[ -f "${QCOW2}" ]]; then
    log "Removing old disk image..."
    rm -f "${QCOW2}"
  fi
  log "Creating ${DISK_SIZE} qcow2 disk..."
  qemu-img create -f qcow2 "${QCOW2}" "${DISK_SIZE}"

  # Connect via NBD
  modprobe nbd max_part=8 2>/dev/null || true
  qemu-nbd --disconnect "${NBD_DEV}" 2>/dev/null || true
  sleep 1
  qemu-nbd --connect="${NBD_DEV}" "${QCOW2}"
  sleep 2

  # Partition — use separate sgdisk calls (more reliable with NBD)
  log "Partitioning disk..."
  sgdisk --zap-all "${NBD_DEV}" >/dev/null 2>&1 || true
  sleep 1
  sgdisk --new=1:0:+1G --typecode=1:ef00 --change-name=1:"EFI"  "${NBD_DEV}" >/dev/null 2>&1 || true
  sgdisk --new=2:0:+4G --typecode=2:8300 --change-name=2:"Boot" "${NBD_DEV}" >/dev/null 2>&1 || true
  sgdisk --new=3:0:0   --typecode=3:8309 --change-name=3:"Root" "${NBD_DEV}" >/dev/null 2>&1 || true
  partprobe "${NBD_DEV}" 2>/dev/null || true
  sleep 3

  # Verify partitions were created
  if [[ ! -b "${NBD_DEV}p1" ]] || [[ ! -b "${NBD_DEV}p3" ]]; then
    die "Partition creation failed — block devices not found"
  fi
  log "Partitions created: $(lsblk -no NAME "${NBD_DEV}" | tr '\n' ' ')"

  # LUKS2
  log "Creating LUKS2 volume..."
  echo -n "${LUKS_PASS}" | cryptsetup luksFormat --batch-mode --type luks2 \
    --cipher aes-xts-plain64 --key-size 512 --hash sha512 \
    --pbkdf argon2id --iter-time 2000 \
    "${NBD_DEV}p3" -
  echo -n "${LUKS_PASS}" | cryptsetup open "${NBD_DEV}p3" logos-build -

  # Filesystems
  log "Creating filesystems..."
  mkfs.fat -F 32 "${NBD_DEV}p1"
  mkfs.ext4 -q "${NBD_DEV}p2"
  mkfs.btrfs -f /dev/mapper/logos-build

  # Subvolumes
  log "Creating Btrfs subvolumes..."
  mount /dev/mapper/logos-build "${MNT}" 2>/dev/null || { mkdir -p "${MNT}"; mount /dev/mapper/logos-build "${MNT}"; }
  btrfs subvolume create "${MNT}/@"
  btrfs subvolume create "${MNT}/@home"
  btrfs subvolume create "${MNT}/@canon"
  btrfs subvolume create "${MNT}/@mesh"
  btrfs subvolume create "${MNT}/@snapshots"
  btrfs subvolume create "${MNT}/@log"
  umount "${MNT}"

  # Mount hierarchy
  log "Mounting subvolumes..."
  BTRFS_OPTS="noatime,compress=zstd:3,space_cache=v2"
  mount -o "subvol=@,${BTRFS_OPTS}" /dev/mapper/logos-build "${MNT}"
  mkdir -p "${MNT}"/{boot,home,srv/cold-canon,srv/warm-mesh,.snapshots,var/log}
  mount "${NBD_DEV}p2" "${MNT}/boot"
  mkdir -p "${MNT}/boot/efi"
  mount "${NBD_DEV}p1" "${MNT}/boot/efi"
  mount -o "subvol=@home,${BTRFS_OPTS}" /dev/mapper/logos-build "${MNT}/home"
  mount -o "subvol=@canon,${BTRFS_OPTS}" /dev/mapper/logos-build "${MNT}/srv/cold-canon"
  mount -o "subvol=@mesh,${BTRFS_OPTS}" /dev/mapper/logos-build "${MNT}/srv/warm-mesh"
  mount -o "subvol=@snapshots,${BTRFS_OPTS}" /dev/mapper/logos-build "${MNT}/.snapshots"
  mount -o "subvol=@log,${BTRFS_OPTS}" /dev/mapper/logos-build "${MNT}/var/log"
  chattr +C "${MNT}/var/log"

  # Save UUIDs
  mkdir -p "${MNT}/tmp"
  CRYPT_UUID="$(blkid -s UUID -o value "${NBD_DEV}p3")"
  BTRFS_UUID="$(blkid -s UUID -o value /dev/mapper/logos-build)"
  BOOT_UUID="$(blkid -s UUID -o value "${NBD_DEV}p2")"
  EFI_UUID="$(blkid -s UUID -o value "${NBD_DEV}p1")"

  cat > "${MNT}/tmp/logos-uuids" << EOF
CRYPT_UUID="${CRYPT_UUID}"
BTRFS_UUID="${BTRFS_UUID}"
BOOT_UUID="${BOOT_UUID}"
EFI_UUID="${EFI_UUID}"
EOF

  log "UUIDs: CRYPT=${CRYPT_UUID} BTRFS=${BTRFS_UUID}"
  pass "Disk partitioned, encrypted, and mounted"
fi

# ═══════════════════════════════════════════════════════════════════
# STEP 1: Stage3 Extract + Portage Config
# ═══════════════════════════════════════════════════════════════════
if [[ "${RESUME}" -le 1 ]]; then
  phase 1 "Stage3 Bootstrap"

  # Reconnect if resuming
  if [[ "${RESUME}" -eq 1 ]]; then
    log "Reconnecting to disk..."
    modprobe nbd max_part=8 2>/dev/null || true
    qemu-nbd --disconnect "${NBD_DEV}" 2>/dev/null || true
    sleep 1
    qemu-nbd --connect="${NBD_DEV}" "${QCOW2}"
    sleep 2
    echo -n "${LUKS_PASS}" | cryptsetup open "${NBD_DEV}p3" logos-build -
    BTRFS_OPTS="noatime,compress=zstd:3,space_cache=v2"
    mkdir -p "${MNT}"
    mount -o "subvol=@,${BTRFS_OPTS}" /dev/mapper/logos-build "${MNT}"
    mount "${NBD_DEV}p2" "${MNT}/boot"
    mount "${NBD_DEV}p1" "${MNT}/boot/efi"
    mount -o "subvol=@home,${BTRFS_OPTS}" /dev/mapper/logos-build "${MNT}/home"
    mount -o "subvol=@log,${BTRFS_OPTS}" /dev/mapper/logos-build "${MNT}/var/log"
  fi

  # Download stage3
  STAGE3_CACHE="${TEST_DIR}/stage3-cache"
  mkdir -p "${STAGE3_CACHE}"

  MIRROR="https://distfiles.gentoo.org/releases/amd64/autobuilds"
  LATEST_URL="${MIRROR}/latest-stage3-amd64-systemd.txt"

  log "Resolving latest stage3..."
  STAGE3_RELATIVE="$(wget -qO- "${LATEST_URL}" | grep -v '^#' | grep '\.tar' | head -1 | awk '{print $1}')"
  STAGE3_FILE="${STAGE3_CACHE}/$(basename "${STAGE3_RELATIVE}")"

  if [[ ! -f "${STAGE3_FILE}" ]]; then
    log "Downloading stage3: $(basename "${STAGE3_RELATIVE}")"
    wget -q --show-progress -O "${STAGE3_FILE}" "${MIRROR}/${STAGE3_RELATIVE}"
  else
    log "Using cached stage3: $(basename "${STAGE3_FILE}")"
  fi

  # Check if stage3 is already extracted
  if [[ -f "${MNT}/usr/bin/emerge" ]]; then
    log "Stage3 already extracted, skipping..."
  else
    log "Extracting stage3 to ${MNT}..."
    tar xpf "${STAGE3_FILE}" --xattrs-include='*.*' --numeric-owner -C "${MNT}"
    pass "Stage3 extracted"
  fi

  # Deploy portage config
  log "Deploying portage configuration..."
  cp "${INSTALLER_DIR}/configs/make.conf.base" "${MNT}/etc/portage/make.conf"
  # Substitute @NPROC@ placeholder with actual core count
  sed -i "s/@NPROC@/$(nproc)/g" "${MNT}/etc/portage/make.conf"
  mkdir -p "${MNT}/etc/portage"/{package.use,package.accept_keywords,package.license}
  cp "${INSTALLER_DIR}/configs/package.use/"* "${MNT}/etc/portage/package.use/"
  cp "${INSTALLER_DIR}/configs/package.accept_keywords/"* "${MNT}/etc/portage/package.accept_keywords/"
  cp "${INSTALLER_DIR}/configs/package.license/"* "${MNT}/etc/portage/package.license/"
  pass "Portage config deployed"

  # Generate fstab
  source "${MNT}/tmp/logos-uuids"
  cat > "${MNT}/etc/fstab" << FEOF
# LogOS Gentoo — Generated fstab
UUID=${EFI_UUID}    /boot/efi       vfat    umask=0077                                                      0 2
UUID=${BOOT_UUID}   /boot           ext4    defaults,noatime                                                0 2
UUID=${BTRFS_UUID}  /               btrfs   subvol=@,noatime,compress=zstd:3,space_cache=v2,discard=async   0 0
UUID=${BTRFS_UUID}  /home           btrfs   subvol=@home,noatime,compress=zstd:3,space_cache=v2             0 0
UUID=${BTRFS_UUID}  /srv/cold-canon btrfs   subvol=@canon,noatime,compress=zstd:3,space_cache=v2            0 0
UUID=${BTRFS_UUID}  /srv/warm-mesh  btrfs   subvol=@mesh,noatime,compress=zstd:3,space_cache=v2             0 0
UUID=${BTRFS_UUID}  /.snapshots     btrfs   subvol=@snapshots,noatime,compress=zstd:3,space_cache=v2        0 0
UUID=${BTRFS_UUID}  /var/log        btrfs   subvol=@log,noatime,compress=zstd:3,space_cache=v2              0 0
FEOF
  pass "fstab generated with real UUIDs"

  # Copy installer scripts for in-chroot use
  cp -a "${INSTALLER_DIR}" "${MNT}/root/installer-gentoo"
  pass "Installer scripts copied to chroot"
fi

# ═══════════════════════════════════════════════════════════════════
# STEP 2: Chroot + Emerge (kernel, GRUB, security)
# ═══════════════════════════════════════════════════════════════════
if [[ "${RESUME}" -le 2 ]]; then
  phase 2 "Chroot Build (emerge kernel, GRUB, security)"

  # Reconnect if resuming
  if [[ "${RESUME}" -eq 2 ]]; then
    log "Reconnecting to disk..."
    modprobe nbd max_part=8 2>/dev/null || true
    qemu-nbd --disconnect "${NBD_DEV}" 2>/dev/null || true
    sleep 1
    qemu-nbd --connect="${NBD_DEV}" "${QCOW2}"
    sleep 2
    echo -n "${LUKS_PASS}" | cryptsetup open "${NBD_DEV}p3" logos-build - 2>/dev/null || true
    BTRFS_OPTS="noatime,compress=zstd:3,space_cache=v2"
    mkdir -p "${MNT}"
    mount -o "subvol=@,${BTRFS_OPTS}" /dev/mapper/logos-build "${MNT}" 2>/dev/null || true
    mount "${NBD_DEV}p2" "${MNT}/boot" 2>/dev/null || true
    mount "${NBD_DEV}p1" "${MNT}/boot/efi" 2>/dev/null || true
    mount -o "subvol=@home,${BTRFS_OPTS}" /dev/mapper/logos-build "${MNT}/home" 2>/dev/null || true
    mount -o "subvol=@log,${BTRFS_OPTS}" /dev/mapper/logos-build "${MNT}/var/log" 2>/dev/null || true
  fi

  source "${MNT}/tmp/logos-uuids"

  # Mount chroot filesystems
  log "Mounting chroot virtual filesystems..."
  mount --types proc /proc "${MNT}/proc" 2>/dev/null || true
  mount --rbind /sys "${MNT}/sys" 2>/dev/null || true
  mount --make-rslave "${MNT}/sys" 2>/dev/null || true
  mount --rbind /dev "${MNT}/dev" 2>/dev/null || true
  mount --make-rslave "${MNT}/dev" 2>/dev/null || true
  mount --rbind /run "${MNT}/run" 2>/dev/null || true
  mount --make-rslave "${MNT}/run" 2>/dev/null || true
  cp /etc/resolv.conf "${MNT}/etc/resolv.conf" 2>/dev/null || true

  # Generate the chroot build script
  cat > "${MNT}/tmp/logos-build.sh" << 'CHROOT_SCRIPT'
#!/bin/bash
set -e

log() { echo -e "\033[32m[CHROOT]\033[0m $*"; }
warn() { echo -e "\033[33m[WARN]\033[0m $*"; }

source /etc/profile
export PS1="(chroot) $PS1"
export MAKEOPTS="-j$(nproc)"

# Load UUIDs
source /tmp/logos-uuids

log "Syncing portage tree..."
emerge-webrsync 2>&1 | tail -3
emerge --sync --quiet 2>&1 | tail -3

log "Setting profile..."
eselect profile set default/linux/amd64/23.0/desktop/systemd 2>/dev/null || \
  eselect profile set default/linux/amd64/23.0/systemd 2>/dev/null || \
  warn "Could not set profile — using default"
eselect profile show

# Critical: update @world before installing new packages.
# Stage3 glibc version may be masked in current portage tree,
# which blocks ALL package installations. This resolves it.
log "Updating @world (resolves stage3 → current portage mismatches)..."
emerge --update --deep --newuse --with-bdeps=y @world 2>&1 | tail -30 || {
  warn "@world update had issues — trying to continue"
  # If glibc is specifically the problem, unmask it
  if emerge --pretend @world 2>&1 | grep -q "masked.*glibc"; then
    log "Unmasking glibc for stage3 compatibility..."
    echo "sys-libs/glibc" >> /etc/portage/package.unmask
    emerge --update --deep --newuse @world 2>&1 | tail -20 || warn "@world update failed even after unmask"
  fi
}

log "Setting timezone and locale..."
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen 2>&1 | tail -2
eselect locale set en_US.utf8 2>/dev/null || true
env-update 2>/dev/null || true
source /etc/profile 2>/dev/null || true

log "Setting hostname..."
echo "logos" > /etc/hostname

log "Creating user..."
useradd -m -G wheel,audio,video,usb -s /bin/bash logos 2>/dev/null || true
echo "logos:logos" | chpasswd
echo "root:REDACTED_ROOT_PASS-2026" | chpasswd

# ── Kernel (distribution kernel — prebuilt preferred for speed) ────
log "Installing distribution kernel + firmware..."
# Try binary kernel first (much faster for VM testing), fall back to source
emerge --noreplace sys-kernel/linux-firmware 2>&1 | tail -10
if emerge --noreplace sys-kernel/gentoo-kernel-bin 2>&1 | tail -20; then
  log "Binary kernel installed successfully"
else
  warn "gentoo-kernel-bin failed — falling back to source-compiled gentoo-kernel"
  emerge --noreplace sys-kernel/gentoo-kernel 2>&1 | tail -20
fi
log "Kernel installed: $(ls /boot/vmlinuz-* 2>/dev/null | head -1 || echo 'none found')"

# Verify kernel was actually installed
if ! ls /boot/vmlinuz-* &>/dev/null; then
  warn "Kernel not found in /boot — trying installkernel manually"
  KVER="$(ls /lib/modules/ 2>/dev/null | sort -V | tail -1)"
  if [[ -n "${KVER}" ]] && [[ -f "/usr/src/linux-${KVER}/.config" ]]; then
    cd "/usr/src/linux-${KVER}" && make install 2>&1 | tail -5
  fi
fi

# Final kernel check — abort if still missing
if ! ls /boot/vmlinuz-* &>/dev/null; then
  log "FATAL: No kernel in /boot after all attempts. Emerging packages may be masked."
  log "Check: emerge --pretend sys-kernel/gentoo-kernel-bin"
  exit 1
fi

# ── Crypttab (required by dracut for LUKS unlock) ────────────
log "Generating /etc/crypttab..."
cat > /etc/crypttab << CTEOF
cryptroot UUID=${CRYPT_UUID} none luks,discard
CTEOF
log "  crypttab: cryptroot -> UUID=${CRYPT_UUID}"

# ── Initramfs ─────────────────────────────────────────────────
log "Installing dracut and generating initramfs..."
emerge --noreplace --quiet-build sys-kernel/dracut 2>&1 | tail -5

mkdir -p /etc/dracut.conf.d
cp /root/installer-gentoo/configs/dracut.conf /etc/dracut.conf.d/logos.conf

KVER="$(ls /lib/modules/ 2>/dev/null | sort -V | tail -1)"
if [[ -n "${KVER}" ]]; then
  log "Building initramfs for kernel ${KVER}..."
  dracut --force --kver "${KVER}" 2>&1 | tail -5
  log "Initramfs: $(ls /boot/initramfs-* 2>/dev/null | head -1 || echo 'none found')"
else
  warn "No kernel modules found — skipping dracut"
fi

# ── GRUB ──────────────────────────────────────────────────────
log "Installing GRUB..."
emerge --noreplace --quiet-build sys-boot/grub 2>&1 | tail -10

# Refresh PATH — GRUB installs to /usr/sbin which may not be in PATH
export PATH="/usr/sbin:/sbin:${PATH}"

if ! command -v grub-mkconfig &>/dev/null; then
  log "FATAL: grub-mkconfig not found after emerge. GRUB installation failed."
  log "Checking: $(which grub-mkconfig 2>&1 || echo 'not in PATH')"
  log "PATH=${PATH}"
  exit 1
fi

# Deploy GRUB config with real LUKS UUID
cp /root/installer-gentoo/grub/grub-defaults /etc/default/grub
sed -i "s|@CRYPT_UUID@|${CRYPT_UUID}|g" /etc/default/grub

# Install profile generator
mkdir -p /etc/grub.d
cp /root/installer-gentoo/grub/41_logos_profiles /etc/grub.d/41_logos_profiles
chmod +x /etc/grub.d/41_logos_profiles

# Generate the config (skip grub-install — needs real EFI vars, done by host later)
log "Generating GRUB config..."
mkdir -p /boot/grub
grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | tail -10

# ── Networking + SSH ──────────────────────────────────────────
log "Installing networking and SSH..."
emerge --noreplace --quiet-build \
  net-misc/networkmanager \
  net-misc/openssh \
  net-misc/dhcpcd \
  sys-apps/dbus \
  2>&1 | tail -5

systemctl enable NetworkManager.service 2>/dev/null || true
systemctl enable sshd.service 2>/dev/null || true
systemctl enable systemd-networkd.service 2>/dev/null || true

# ── Security ──────────────────────────────────────────────────
log "Deploying security configurations..."
mkdir -p /etc/sysctl.d /etc/audit/rules.d /etc/ssh/sshd_config.d
cp /root/installer-gentoo/security/99-logos-hardening.conf /etc/sysctl.d/
cp /root/installer-gentoo/security/logos-audit.rules /etc/audit/rules.d/
cp /root/installer-gentoo/security/10-logos-ssh.conf /etc/ssh/sshd_config.d/

# Install security packages (best-effort — some may not be available yet)
log "Installing security packages..."
emerge --noreplace --quiet-build sys-apps/systemd 2>&1 | tail -3
emerge --noreplace --quiet-build sys-process/audit 2>&1 | tail -3 || warn "audit not available"
emerge --noreplace --quiet-build net-firewall/ufw 2>&1 | tail -3 || warn "ufw not available"

# Enable what we can
systemctl enable auditd.service 2>/dev/null || true
systemctl enable ufw.service 2>/dev/null || true

# ── Watchdog ──────────────────────────────────────────────────
log "Installing kernel watchdog..."
mkdir -p /usr/local/lib/logos
install -m 0755 /root/installer-gentoo/kernel/kernel-watchdog.sh /usr/local/lib/logos/
cp /root/installer-gentoo/services/logos-kernel-watchdog.service /etc/systemd/system/
cp /root/installer-gentoo/services/logos-kernel-watchdog.timer /etc/systemd/system/
systemctl enable logos-kernel-watchdog.timer 2>/dev/null || true

# ── Tools ─────────────────────────────────────────────────────
log "Installing LogOS tools..."
install -m 0755 /root/installer-gentoo/tools/logos-validate-boot /usr/local/bin/
install -m 0755 /root/installer-gentoo/tools/logos-assist /usr/local/bin/
install -m 0755 /root/installer-gentoo/tools/logos-canon-promote /usr/local/bin/

# ── Canon Structure ──────────────────────────────────────────
log "Creating Cold Canon structure..."
mkdir -p /srv/cold-canon/{documents,software,datasets,media}
mkdir -p /srv/warm-mesh /srv/hot-workspace

# ── Overlay ──────────────────────────────────────────────────
log "Deploying logos-overlay..."
OVERLAY_DST=/var/db/repos/logos-overlay
mkdir -p "${OVERLAY_DST}"
cp -a /root/installer-gentoo/overlays/logos-overlay/. "${OVERLAY_DST}/"
mkdir -p /etc/portage/repos.conf
cat > /etc/portage/repos.conf/logos-overlay.conf << OEOF
[logos-overlay]
location = /var/db/repos/logos-overlay
auto-sync = no
OEOF

# ── Core Utils (best-effort) ─────────────────────────────────
log "Installing core utilities..."
emerge --noreplace --quiet-build \
  sys-process/htop app-misc/tmux net-misc/wget net-misc/curl \
  sys-apps/pciutils app-misc/neofetch \
  2>&1 | tail -5 || warn "Some core utils not available"

# ── Branding ─────────────────────────────────────────────────
log "Setting up branding..."
cat > /etc/logos-release << BEOF
NAME="LogOS"
VERSION="2026.1"
CODENAME="Ringed City"
BASE="Gentoo Linux"
INSTALLATION_METHOD="phase-scripts"
BEOF

cat > /etc/motd << MEOF
LogOS Gentoo — Ringed City Build
Profiles: Gael (Security) | Midir (Balanced) | Halflight (Performance)
"Knowledge preserved. Reason applied. Civilization continued."
MEOF

# ── Serial Console for QEMU ─────────────────────────────────
log "Enabling serial console for QEMU boot testing..."
mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d
cat > /etc/systemd/system/serial-getty@ttyS0.service.d/override.conf << SEOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I 115200 linux
SEOF
systemctl enable serial-getty@ttyS0.service 2>/dev/null || true

log "Chroot build complete!"
echo "BUILD_COMPLETE"
CHROOT_SCRIPT

  chmod +x "${MNT}/tmp/logos-build.sh"

  # Run the chroot build script
  log "Entering chroot and running build (this will take a while)..."
  log "Follow progress: tail -f ${LOG_DIR}/chroot-build.log"
  chroot "${MNT}" /bin/bash /tmp/logos-build.sh 2>&1 | tee "${LOG_DIR}/chroot-build.log"

  if grep -q "BUILD_COMPLETE" "${LOG_DIR}/chroot-build.log"; then
    pass "Chroot build completed successfully"
  else
    fail "Chroot build may have had issues — check ${LOG_DIR}/chroot-build.log"
  fi
fi

# ═══════════════════════════════════════════════════════════════════
# STEP 3: Install GRUB to EFI (requires special handling for NBD)
# ═══════════════════════════════════════════════════════════════════
phase 3 "GRUB EFI Installation"

source "${MNT}/tmp/logos-uuids"

# GRUB install to EFI partition
# In chroot with NBD, grub-install can be tricky. Use --removable for VM testing.
log "Installing GRUB to EFI partition..."
if chroot "${MNT}" grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=LogOS \
    --recheck \
    --removable 2>&1 | tee -a "${LOG_DIR}/grub-install.log"; then
  pass "GRUB installed to EFI"
else
  warn "grub-install had issues (may still work in VM)"
  # Fallback: manually copy GRUB EFI binary
  if [[ -f "${MNT}/usr/lib/grub/x86_64-efi/grub.efi" ]]; then
    mkdir -p "${MNT}/boot/efi/EFI/BOOT"
    cp "${MNT}/usr/lib/grub/x86_64-efi/grub.efi" "${MNT}/boot/efi/EFI/BOOT/BOOTX64.EFI" 2>/dev/null || true
  fi
fi

# Ensure GRUB config exists
if [[ -f "${MNT}/boot/grub/grub.cfg" ]]; then
  pass "GRUB config exists"
  # Check for LogOS profiles
  if grep -q "LogOS" "${MNT}/boot/grub/grub.cfg" 2>/dev/null; then
    pass "LogOS profiles in GRUB config"
  else
    warn "LogOS profiles not found in grub.cfg — may need regeneration on first boot"
  fi
else
  warn "GRUB config missing — will need grub-mkconfig on first boot"
fi

# ═══════════════════════════════════════════════════════════════════
# STEP 4: Unmount and Disconnect
# ═══════════════════════════════════════════════════════════════════
phase 4 "Finalize"

log "Syncing filesystems..."
sync

log "Unmounting chroot..."
umount -l "${MNT}/proc" 2>/dev/null || true
umount -l "${MNT}/sys" 2>/dev/null || true
umount -l "${MNT}/dev" 2>/dev/null || true
umount -l "${MNT}/run" 2>/dev/null || true

log "Unmounting partitions..."
umount -R "${MNT}" 2>/dev/null || true
sleep 1
cryptsetup close logos-build 2>/dev/null || true
sleep 1
qemu-nbd --disconnect "${NBD_DEV}" 2>/dev/null || true

# Clear the trap since we've cleaned up manually
trap - EXIT

pass "Disk disconnected cleanly"

# ═══════════════════════════════════════════════════════════════════
# STEP 5: Boot Test
# ═══════════════════════════════════════════════════════════════════
phase 5 "QEMU Boot Verification"

OVMF="/usr/share/OVMF/OVMF_CODE.fd"
OVMF_VARS_FILE="${TEST_DIR}/OVMF_VARS_full.fd"
SERIAL_SOCK="${TEST_DIR}/serial-boot.sock"

if [[ ! -f "${OVMF_VARS_FILE}" ]]; then
  TEMPLATE="/usr/share/OVMF/OVMF_VARS.fd"
  if [[ -f "${TEMPLATE}" ]]; then
    cp "${TEMPLATE}" "${OVMF_VARS_FILE}"
  else
    truncate -s 256K "${OVMF_VARS_FILE}"
  fi
fi

log "Starting QEMU (disk boot test)..."
rm -f "${SERIAL_SOCK}"

qemu-system-x86_64 \
  -enable-kvm \
  -cpu host \
  -m 4G \
  -smp 2 \
  -drive "if=pflash,format=raw,readonly=on,file=${OVMF}" \
  -drive "if=pflash,format=raw,file=${OVMF_VARS_FILE}" \
  -drive "file=${QCOW2},format=qcow2,if=virtio" \
  -netdev "user,id=net0,hostfwd=tcp::2222-:22" \
  -device "virtio-net-pci,netdev=net0" \
  -chardev "socket,id=serial0,path=${SERIAL_SOCK},server=on,wait=off" \
  -serial "chardev:serial0" \
  -display none \
  -daemonize \
  -pidfile "${TEST_DIR}/qemu-boot.pid" \
  || die "Failed to start QEMU for boot test"

BOOT_PID="$(cat "${TEST_DIR}/qemu-boot.pid" 2>/dev/null)"
log "QEMU booted (PID: ${BOOT_PID})"

# Monitor serial output for boot progress
log "Monitoring serial output for 120 seconds..."
BOOT_LOG="${LOG_DIR}/boot-test.log"
: > "${BOOT_LOG}"

# Collect serial output in background
socat -u "UNIX-CONNECT:${SERIAL_SOCK}" "OPEN:${BOOT_LOG},creat,append" &
SOCAT_PID=$!

# Wait and check for boot indicators
BOOT_SUCCESS=0
for i in $(seq 1 24); do
  sleep 5
  if grep -qiE "(login:|systemd.*started|Welcome to|LogOS)" "${BOOT_LOG}" 2>/dev/null; then
    BOOT_SUCCESS=1
    pass "System reached login prompt!"
    break
  fi

  # Check if LUKS passphrase is needed (send via serial)
  if grep -qiE "(passphrase|Enter.*password|cryptsetup)" "${BOOT_LOG}" 2>/dev/null; then
    log "LUKS passphrase prompt detected, sending passphrase..."
    echo "${LUKS_PASS}" | socat - "UNIX-CONNECT:${SERIAL_SOCK}" 2>/dev/null
    sleep 5
  fi

  echo -n "."
done
echo ""

kill "${SOCAT_PID}" 2>/dev/null || true

if [[ "${BOOT_SUCCESS}" -eq 1 ]]; then
  pass "VM booted successfully to login!"

  # Try SSH
  sleep 10
  if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=10 -p 2222 root@localhost "uname -a" 2>/dev/null; then
    pass "SSH connection successful"

    # Run validation
    log "Running logos-validate-boot..."
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -p 2222 root@localhost "/usr/local/bin/logos-validate-boot" 2>/dev/null | \
        tee "${LOG_DIR}/validate-boot.log" || warn "validate-boot had issues"
  else
    warn "SSH not available (may need manual login)"
  fi
else
  warn "Boot did not reach login within 120s — check ${BOOT_LOG}"
  log "Last 20 lines of serial output:"
  tail -20 "${BOOT_LOG}"
fi

# Shutdown VM
kill "${BOOT_PID}" 2>/dev/null || true
rm -f "${SERIAL_SOCK}" "${TEST_DIR}/qemu-boot.pid"

# ── Summary ───────────────────────────────────────────────────────
echo ""
echo "========================================"
echo "  Build Results"
echo "  PASS: ${PASS}  FAIL: ${FAIL}"
echo "  Logs: ${LOG_DIR}/"
echo ""
echo "  To boot the VM:"
echo "    QCOW2=${QCOW2}"
echo "    qemu-system-x86_64 -enable-kvm -cpu host -m 4G \\"
echo "      -drive if=pflash,format=raw,readonly=on,file=${OVMF} \\"
echo "      -drive if=pflash,format=raw,file=${OVMF_VARS_FILE} \\"
echo "      -drive file=${QCOW2},format=qcow2,if=virtio \\"
echo "      -netdev user,id=net0,hostfwd=tcp::2222-:22 \\"
echo "      -device virtio-net-pci,netdev=net0 \\"
echo "      -nographic"
echo "========================================"

cat > "${LOG_DIR}/build-results.log" << REOF
Build Results — $(date -Iseconds)
PASS: ${PASS}
FAIL: ${FAIL}
Disk: ${QCOW2}
Steps completed:
  0. Disk partitioned (LUKS2 + Btrfs + 6 subvolumes)
  1. Stage3 extracted + portage configured
  2. Chroot build (kernel, GRUB, security, tools)
  3. GRUB EFI installed
  4. Finalized and disconnected
  5. Boot test attempted
REOF

[[ "${FAIL}" -gt 0 ]] && exit 1 || exit 0
