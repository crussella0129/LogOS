#!/usr/bin/env bash
# LogOS Gentoo — Phase 1: Stage3 Bootstrap
# Download, verify, extract stage3; configure portage; chroot setup
#
# Prerequisites: Phase 0 completed (disk mounted at /mnt)
#
# Usage: ./phase1-stage3.sh [--stage3 /path/to/stage3.tar.xz]
#        TARGET_USER=charles TARGET_HOSTNAME=logos ./phase1-stage3.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

require_root
require_cmds wget tar gpg

# ── Configuration ─────────────────────────────────────────────────
TARGET_USER="${TARGET_USER:-logos}"
TARGET_HOSTNAME="${TARGET_HOSTNAME:-logos}"
TARGET_TIMEZONE="${TARGET_TIMEZONE:-America/New_York}"
TARGET_LOCALE="${TARGET_LOCALE:-en_US.UTF-8}"
STAGE3_PATH=""
STAGE3_MIRROR="${STAGE3_MIRROR:-https://distfiles.gentoo.org}"
STAGE3_FLAVOR="stage3-amd64-systemd"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stage3) STAGE3_PATH="$2"; shift 2 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

# ── Verify mounts ─────────────────────────────────────────────────
if ! mountpoint -q /mnt; then
  die "/mnt is not mounted. Run phase0-partition.sh first."
fi

# Load UUIDs from phase0
if [[ -f /mnt/tmp/logos-uuids ]]; then
  source /mnt/tmp/logos-uuids
  log "Loaded UUIDs from phase0"
else
  warn "No UUID file found — GRUB config will need manual UUID setup"
fi

# ── Download Stage3 ───────────────────────────────────────────────
if [[ -z "${STAGE3_PATH}" ]]; then
  log "Fetching latest stage3 tarball URL"
  LATEST_URL="${STAGE3_MIRROR}/releases/amd64/autobuilds/latest-${STAGE3_FLAVOR}.txt"
  STAGE3_RELATIVE="$(wget -qO- "${LATEST_URL}" | grep -v '^#' | grep '\.tar' | head -1 | awk '{print $1}')"

  if [[ -z "${STAGE3_RELATIVE}" ]]; then
    die "Failed to determine latest stage3 URL"
  fi

  STAGE3_URL="${STAGE3_MIRROR}/releases/amd64/autobuilds/${STAGE3_RELATIVE}"
  STAGE3_BASENAME="$(basename "${STAGE3_RELATIVE}")"

  log "Downloading ${STAGE3_BASENAME}"
  wget -c "${STAGE3_URL}" -O "/tmp/${STAGE3_BASENAME}"
  wget -c "${STAGE3_URL}.asc" -O "/tmp/${STAGE3_BASENAME}.asc"

  log "Verifying GPG signature"
  # Import Gentoo release keys
  wget -qO- https://qa-reports.gentoo.org/output/service-keys.gpg | gpg --import 2>/dev/null || true
  if gpg --verify "/tmp/${STAGE3_BASENAME}.asc" "/tmp/${STAGE3_BASENAME}" 2>/dev/null; then
    log "GPG signature verified"
  else
    warn "GPG verification failed — proceeding with caution"
    confirm "Continue anyway?" || die "Aborted."
  fi

  STAGE3_PATH="/tmp/${STAGE3_BASENAME}"
fi

if [[ ! -f "${STAGE3_PATH}" ]]; then
  die "Stage3 tarball not found: ${STAGE3_PATH}"
fi

# ── Extract Stage3 ────────────────────────────────────────────────
log "Extracting stage3 to /mnt"
tar xpf "${STAGE3_PATH}" --xattrs-include='*.*' --numeric-owner -C /mnt

# ── Install Portage Configuration ────────────────────────────────
log "Installing LogOS portage configuration"
cp "${SCRIPT_DIR}/configs/make.conf.base" /mnt/etc/portage/make.conf
# Substitute @NPROC@ placeholder with actual core count
sed -i "s/@NPROC@/$(nproc)/g" /mnt/etc/portage/make.conf

mkdir -p /mnt/etc/portage/package.use
cp "${SCRIPT_DIR}"/configs/package.use/* /mnt/etc/portage/package.use/

mkdir -p /mnt/etc/portage/package.accept_keywords
cp "${SCRIPT_DIR}"/configs/package.accept_keywords/* /mnt/etc/portage/package.accept_keywords/

mkdir -p /mnt/etc/portage/package.license
cp "${SCRIPT_DIR}"/configs/package.license/* /mnt/etc/portage/package.license/

# ── Copy DNS and mount virtual filesystems ────────────────────────
log "Preparing chroot environment"
cp --dereference /etc/resolv.conf /mnt/etc/

mount --types proc  /proc /mnt/proc
mount --rbind       /sys  /mnt/sys
mount --make-rslave       /mnt/sys
mount --rbind       /dev  /mnt/dev
mount --make-rslave       /mnt/dev
mount --bind        /run  /mnt/run

# ── Generate chroot script ────────────────────────────────────────
log "Generating chroot configuration script"
cat > /mnt/tmp/logos-chroot-setup.sh << CHROOT_EOF
#!/usr/bin/env bash
set -euo pipefail

log() { echo "[chroot] \$*"; }

# ── Portage sync ──────────────────────────────────────────────
log "Syncing portage tree"
emerge-webrsync
emerge --sync --quiet

# ── Profile selection ─────────────────────────────────────────
log "Setting systemd profile"
eselect profile set default/linux/amd64/23.0/desktop/systemd

# ── Update @world ─────────────────────────────────────────────
log "Updating @world set (this will take a while)"
emerge --update --deep --newuse --quiet @world

# ── Timezone ──────────────────────────────────────────────────
log "Setting timezone to ${TARGET_TIMEZONE}"
ln -sf /usr/share/zoneinfo/${TARGET_TIMEZONE} /etc/localtime
echo "${TARGET_TIMEZONE}" > /etc/timezone
emerge --config sys-libs/timezone-data 2>/dev/null || true

# ── Locale ────────────────────────────────────────────────────
log "Configuring locale"
cat > /etc/locale.gen << 'LOCALE_EOF'
en_US.UTF-8 UTF-8
en_US ISO-8859-1
LOCALE_EOF
locale-gen
eselect locale set ${TARGET_LOCALE}
env-update
source /etc/profile

# ── Hostname ──────────────────────────────────────────────────
log "Setting hostname to ${TARGET_HOSTNAME}"
echo "${TARGET_HOSTNAME}" > /etc/hostname
cat > /etc/hosts << HOSTS_EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${TARGET_HOSTNAME}.localdomain ${TARGET_HOSTNAME}
HOSTS_EOF

# ── Fstab ─────────────────────────────────────────────────────
log "Generating fstab"
cat > /etc/fstab << FSTAB_EOF
# LogOS Gentoo fstab — generated by phase1-stage3.sh
# <device>                                <mount>           <type>  <options>                                              <dump> <pass>
UUID=${BTRFS_UUID:-REPLACE_ME}  /                 btrfs   subvol=@,noatime,compress=zstd:3,space_cache=v2,discard=async     0      0
UUID=${BTRFS_UUID:-REPLACE_ME}  /home             btrfs   subvol=@home,noatime,compress=zstd:3,space_cache=v2,discard=async 0      0
UUID=${BTRFS_UUID:-REPLACE_ME}  /srv/cold-canon   btrfs   subvol=@canon,noatime,compress=zstd:3,space_cache=v2              0      0
UUID=${BTRFS_UUID:-REPLACE_ME}  /srv/warm-mesh    btrfs   subvol=@mesh,noatime,compress=zstd:3,space_cache=v2               0      0
UUID=${BTRFS_UUID:-REPLACE_ME}  /.snapshots       btrfs   subvol=@snapshots,noatime,compress=zstd:3,space_cache=v2          0      0
UUID=${BTRFS_UUID:-REPLACE_ME}  /var/log          btrfs   subvol=@log,noatime,nodatacow                                    0      0
UUID=${BOOT_UUID:-REPLACE_ME}   /boot             ext4    defaults                                                          0      2
UUID=${EFI_UUID:-REPLACE_ME}    /boot/efi         vfat    umask=0077                                                        0      1
FSTAB_EOF

# ── Essential packages ────────────────────────────────────────
log "Installing essential packages"
emerge --noreplace --quiet \
  sys-kernel/linux-firmware \
  sys-kernel/installkernel \
  sys-kernel/dracut \
  sys-fs/cryptsetup \
  sys-fs/btrfs-progs \
  sys-boot/grub \
  net-misc/networkmanager \
  app-admin/sudo \
  app-editors/vim \
  sys-process/cronie

# ── Create user ───────────────────────────────────────────────
log "Creating user ${TARGET_USER}"
if ! id "${TARGET_USER}" &>/dev/null; then
  useradd -m -G wheel,audio,video,usb,plugdev -s /bin/bash "${TARGET_USER}"
  echo "Set password for ${TARGET_USER}:"
  passwd "${TARGET_USER}"
fi

# Enable sudo for wheel group
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# ── Enable services ──────────────────────────────────────────
log "Enabling base services"
systemctl enable NetworkManager.service
systemctl enable cronie.service
systemctl enable systemd-timesyncd.service

# ── Set root password ─────────────────────────────────────────
log "Set root password:"
passwd

log "Chroot setup complete."
CHROOT_EOF

chmod +x /mnt/tmp/logos-chroot-setup.sh

# ── Enter chroot ──────────────────────────────────────────────────
log "Entering chroot — running configuration"
chroot /mnt /bin/bash -c "source /etc/profile && /tmp/logos-chroot-setup.sh"

log "Phase 1 complete. System is bootstrapped."
log "Next: chroot /mnt and run phase2-transform.sh"
