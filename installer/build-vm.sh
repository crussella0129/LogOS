#!/usr/bin/env bash
# build-vm.sh — Build a bootable LogOS Gentoo VM image
#
# Single self-contained script. Uses losetup (not NBD), raw image (not qcow2).
# Produces a QEMU-bootable qcow2 with LUKS2-encrypted Btrfs root.
#
# Usage: sudo ./installer/build-vm.sh
#
# Phase A: boots to login prompt. No desktop, no security hardening.

set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers (defined early — needed by interactive setup below)
# ---------------------------------------------------------------------------
log()  { echo "[$(date +%H:%M:%S)] $*"; }
die()  { log "FATAL: $*"; exit 1; }
step() { echo; log "========== STEP $1: $2 =========="; }

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}/build"
IMG_RAW="${WORK_DIR}/logos-vm.raw"
IMG_QCOW2="${WORK_DIR}/logos-vm.qcow2"
MNT="${WORK_DIR}/mnt"
LOG_DIR="${SCRIPT_DIR}/logs"
CHROOT_LOG="${LOG_DIR}/chroot.log"
DISK_SIZE="30G"
LUKS_NAME="cryptroot"
HOSTNAME="logos"

# ---------------------------------------------------------------------------
# Interactive setup — username and passwords with confirmation
# ---------------------------------------------------------------------------
confirm_password() {
    local label="$1" varname="$2" pass1 pass2
    while true; do
        read -rsp "Enter ${label}: " pass1; echo
        [[ -n "${pass1}" ]] || { echo "  Cannot be empty. Try again."; continue; }
        read -rsp "Confirm ${label}: " pass2; echo
        if [[ "${pass1}" == "${pass2}" ]]; then
            eval "${varname}=\${pass1}"
            return
        fi
        echo "  Passwords do not match. Try again."
    done
}

# Username
if [[ -n "${LOGOS_USER_NAME:-}" ]]; then
    USER_NAME="${LOGOS_USER_NAME}"
else
    read -rp "Enter username for the VM [logos]: " USER_NAME
    USER_NAME="${USER_NAME:-logos}"
    # Validate: lowercase, starts with letter, no spaces
    if [[ ! "${USER_NAME}" =~ ^[a-z][a-z0-9_-]*$ ]]; then
        die "Invalid username '${USER_NAME}' — must be lowercase, start with a letter, no spaces"
    fi
fi

# LUKS passphrase — a typo here bricks the entire build
if [[ -n "${LOGOS_LUKS_PASS:-}" ]]; then
    LUKS_PASS="${LOGOS_LUKS_PASS}"
else
    echo ""
    echo "  IMPORTANT: If you mistype the LUKS passphrase, the disk will be"
    echo "  permanently unrecoverable. You will be asked to type it twice."
    echo ""
    confirm_password "LUKS passphrase" LUKS_PASS
fi

# Root password
if [[ -n "${LOGOS_ROOT_PASS:-}" ]]; then
    ROOT_PASS="${LOGOS_ROOT_PASS}"
else
    confirm_password "root password" ROOT_PASS
fi

# User password
if [[ -n "${LOGOS_USER_PASS:-}" ]]; then
    USER_PASS="${LOGOS_USER_PASS}"
else
    confirm_password "password for user '${USER_NAME}'" USER_PASS
fi
STAGE3_CACHE="${WORK_DIR}/stage3-cache"
STAGE3_MIRROR="https://distfiles.gentoo.org/releases/amd64/autobuilds"

# Partition sizes
EFI_SIZE="1G"
BOOT_SIZE="1G"
# Root = remainder

# ---------------------------------------------------------------------------
# Cleanup trap — robust teardown
# ---------------------------------------------------------------------------
cleanup() {
    log "Cleaning up..."
    for mp in "${MNT}/boot/efi" "${MNT}/boot" "${MNT}/home" "${MNT}/var/log" "${MNT}/.snapshots" "${MNT}/proc" "${MNT}/sys" "${MNT}/dev/pts" "${MNT}/dev" "${MNT}/run" "${MNT}"; do
        umount -l "${mp}" 2>/dev/null || true
    done
    cryptsetup close "${LUKS_NAME}" 2>/dev/null || true
    [[ -n "${LOOP_DEV:-}" ]] && losetup -d "${LOOP_DEV}" 2>/dev/null || true
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
[[ "$(id -u)" -eq 0 ]] || die "Must run as root"
command -v sgdisk    >/dev/null || die "sgdisk not found (sys-apps/gptfdisk)"
command -v cryptsetup >/dev/null || die "cryptsetup not found"
command -v mkfs.fat  >/dev/null || die "mkfs.fat not found (sys-fs/dosfstools)"
command -v mkfs.ext4 >/dev/null || die "mkfs.ext4 not found"
command -v mkfs.btrfs >/dev/null || die "mkfs.btrfs not found (sys-fs/btrfs-progs)"
command -v qemu-img  >/dev/null || die "qemu-img not found (app-emulation/qemu)"
command -v qemu-system-x86_64 >/dev/null || die "qemu-system-x86_64 not found"

mkdir -p "${WORK_DIR}" "${MNT}" "${LOG_DIR}" "${STAGE3_CACHE}"

# Clean up leftovers from any previous failed build
if [[ -e "/dev/mapper/${LUKS_NAME}" ]]; then
    log "Closing stale LUKS mapping '${LUKS_NAME}' from previous run"
    # Unmount everything under MNT (reverse order to handle nested mounts)
    if mountpoint -q "${MNT}" 2>/dev/null || mount | grep -q "${MNT}"; then
        for mp in $(mount | grep "${MNT}" | awk '{print $3}' | sort -r); do
            umount -l "${mp}" 2>/dev/null || true
        done
    fi
    # Force close LUKS — dmsetup as fallback if cryptsetup fails
    cryptsetup close "${LUKS_NAME}" 2>/dev/null || {
        log "cryptsetup close failed, trying dmsetup remove"
        dmsetup remove --force "${LUKS_NAME}" 2>/dev/null || true
    }
    # Verify it's gone
    if [[ -e "/dev/mapper/${LUKS_NAME}" ]]; then
        die "Cannot remove stale /dev/mapper/${LUKS_NAME} — reboot may be required"
    fi
fi
# Detach any loop devices still pointing at our image
for ld in $(losetup -j "${IMG_RAW}" 2>/dev/null | cut -d: -f1); do
    log "Detaching stale loop device ${ld}"
    losetup -d "${ld}" 2>/dev/null || true
done

# ---------------------------------------------------------------------------
# STEP 1: Create raw disk image
# ---------------------------------------------------------------------------
step 1 "Create raw disk image (${DISK_SIZE})"

if [[ -f "${IMG_RAW}" ]]; then
    log "Removing existing raw image"
    rm -f "${IMG_RAW}"
fi
truncate -s "${DISK_SIZE}" "${IMG_RAW}"
log "Created ${IMG_RAW}"

# ---------------------------------------------------------------------------
# STEP 2: Attach loop device
# ---------------------------------------------------------------------------
step 2 "Attach loop device"

LOOP_DEV="$(losetup --find --show --partscan "${IMG_RAW}")"
log "Loop device: ${LOOP_DEV}"

# Wait for partition devices to appear
sleep 1

# ---------------------------------------------------------------------------
# STEP 3: Partition (GPT: EFI + Boot + Root)
# ---------------------------------------------------------------------------
step 3 "Partition disk"

sgdisk --zap-all "${LOOP_DEV}"
sgdisk --new=1:0:+"${EFI_SIZE}"  --typecode=1:EF00 --change-name=1:"EFI"  "${LOOP_DEV}"
sgdisk --new=2:0:+"${BOOT_SIZE}" --typecode=2:8300 --change-name=2:"Boot" "${LOOP_DEV}"
sgdisk --new=3:0:0               --typecode=3:8309 --change-name=3:"Root" "${LOOP_DEV}"
sgdisk --print "${LOOP_DEV}"

# Re-read partition table
partprobe "${LOOP_DEV}" 2>/dev/null || true
sleep 1

# Determine partition device naming (loop0p1 vs loop0s1)
if [[ -e "${LOOP_DEV}p1" ]]; then
    PART_PREFIX="${LOOP_DEV}p"
elif [[ -e "${LOOP_DEV}s1" ]]; then
    PART_PREFIX="${LOOP_DEV}s"
else
    die "Partition devices not found for ${LOOP_DEV}"
fi

EFI_DEV="${PART_PREFIX}1"
BOOT_DEV="${PART_PREFIX}2"
ROOT_DEV="${PART_PREFIX}3"

log "EFI:  ${EFI_DEV}"
log "Boot: ${BOOT_DEV}"
log "Root: ${ROOT_DEV}"

# ---------------------------------------------------------------------------
# STEP 4: LUKS2 + Btrfs
# ---------------------------------------------------------------------------
step 4 "Create LUKS2 + Btrfs"

# Format LUKS2 with Argon2id
echo -n "${LUKS_PASS}" | cryptsetup luksFormat --batch-mode \
    --type luks2 \
    --cipher aes-xts-plain64 \
    --key-size 512 \
    --hash sha512 \
    --pbkdf argon2id \
    "${ROOT_DEV}" -

# Open LUKS
echo -n "${LUKS_PASS}" | cryptsetup open --type luks2 "${ROOT_DEV}" "${LUKS_NAME}" -

CRYPT_DEV="/dev/mapper/${LUKS_NAME}"

# Format filesystems
mkfs.fat -F 32 "${EFI_DEV}"
mkfs.ext4 -q "${BOOT_DEV}"
mkfs.btrfs -f "${CRYPT_DEV}"

# Create Btrfs subvolumes
mount "${CRYPT_DEV}" "${MNT}"
btrfs subvolume create "${MNT}/@"
btrfs subvolume create "${MNT}/@home"
btrfs subvolume create "${MNT}/@snapshots"
btrfs subvolume create "${MNT}/@log"
umount "${MNT}"

# Mount with subvolumes
mount -o compress=zstd:3,subvol=@ "${CRYPT_DEV}" "${MNT}"
mkdir -p "${MNT}/home" "${MNT}/.snapshots" "${MNT}/var/log" "${MNT}/boot"
mount -o compress=zstd:3,subvol=@home      "${CRYPT_DEV}" "${MNT}/home"
mount -o compress=zstd:3,subvol=@snapshots "${CRYPT_DEV}" "${MNT}/.snapshots"
mount -o compress=zstd:3,subvol=@log       "${CRYPT_DEV}" "${MNT}/var/log"

# nodatacow on log subvolume (per-inode attribute, not mount option)
chattr +C "${MNT}/var/log"

# Mount boot + EFI
mount "${BOOT_DEV}" "${MNT}/boot"
mkdir -p "${MNT}/boot/efi"
mount "${EFI_DEV}" "${MNT}/boot/efi"

log "All filesystems mounted"

# ---------------------------------------------------------------------------
# STEP 5: Capture UUIDs
# ---------------------------------------------------------------------------
step 5 "Capture UUIDs"

EFI_UUID="$(blkid -s UUID -o value "${EFI_DEV}")"
BOOT_UUID="$(blkid -s UUID -o value "${BOOT_DEV}")"
CRYPT_UUID="$(blkid -s UUID -o value "${ROOT_DEV}")"   # LUKS container UUID
BTRFS_UUID="$(blkid -s UUID -o value "${CRYPT_DEV}")"  # Inner Btrfs UUID

[[ -n "${EFI_UUID}" ]]   || die "Failed to get EFI UUID"
[[ -n "${BOOT_UUID}" ]]  || die "Failed to get Boot UUID"
[[ -n "${CRYPT_UUID}" ]] || die "Failed to get LUKS UUID"
[[ -n "${BTRFS_UUID}" ]] || die "Failed to get Btrfs UUID"

log "EFI UUID:   ${EFI_UUID}"
log "Boot UUID:  ${BOOT_UUID}"
log "LUKS UUID:  ${CRYPT_UUID}"
log "Btrfs UUID: ${BTRFS_UUID}"

# ---------------------------------------------------------------------------
# STEP 6: Stage3 download + extract
# ---------------------------------------------------------------------------
step 6 "Stage3 download + extract"

# Find latest stage3 tarball URL
LATEST_URL="${STAGE3_MIRROR}/latest-stage3-amd64-systemd.txt"
log "Fetching latest stage3 list from ${LATEST_URL}"

STAGE3_LINE="$(curl -sL "${LATEST_URL}" | grep -v '^#' | grep '\.tar' | head -n1)"
[[ -n "${STAGE3_LINE}" ]] || die "Failed to parse stage3 listing"

STAGE3_FILE="$(echo "${STAGE3_LINE}" | awk '{print $1}')"
STAGE3_URL="${STAGE3_MIRROR}/${STAGE3_FILE}"
STAGE3_BASENAME="$(basename "${STAGE3_FILE}")"
STAGE3_LOCAL="${STAGE3_CACHE}/${STAGE3_BASENAME}"

if [[ -f "${STAGE3_LOCAL}" ]]; then
    log "Using cached stage3: ${STAGE3_LOCAL}"
else
    log "Downloading stage3: ${STAGE3_URL}"
    curl -L -o "${STAGE3_LOCAL}" "${STAGE3_URL}" || die "Stage3 download failed"
fi

log "Extracting stage3 into ${MNT}"
tar xpf "${STAGE3_LOCAL}" --xattrs-include='*.*' --numeric-owner -C "${MNT}" \
    || die "Stage3 extraction failed"
log "Stage3 extracted"

# ---------------------------------------------------------------------------
# STEP 7: Deploy configs
# ---------------------------------------------------------------------------
step 7 "Deploy configs"

NPROC="$(nproc)"

# make.conf — substitute @NPROC@ placeholder
sed "s/@NPROC@/${NPROC}/g" "${SCRIPT_DIR}/configs/make.conf" \
    > "${MNT}/etc/portage/make.conf"

# package.use
mkdir -p "${MNT}/etc/portage/package.use"
cp "${SCRIPT_DIR}/configs/package.use/logos" "${MNT}/etc/portage/package.use/logos"

# package.license
mkdir -p "${MNT}/etc/portage/package.license"
cp "${SCRIPT_DIR}/configs/package.license/logos" "${MNT}/etc/portage/package.license/logos"

# DNS (needed for emerge)
cp -L /etc/resolv.conf "${MNT}/etc/resolv.conf"

# --- Generate fstab ---
cat > "${MNT}/tmp/fstab" <<FSTAB
# /etc/fstab — LogOS Gentoo
# <device>                                <mount>       <type>   <options>                          <dump> <pass>
UUID=${EFI_UUID}                           /boot/efi     vfat     defaults,noatime                   0      2
UUID=${BOOT_UUID}                          /boot         ext4     defaults,noatime                   0      2
UUID=${BTRFS_UUID}                         /             btrfs    defaults,compress=zstd:3,subvol=@            0      0
UUID=${BTRFS_UUID}                         /home         btrfs    defaults,compress=zstd:3,subvol=@home        0      0
UUID=${BTRFS_UUID}                         /.snapshots   btrfs    defaults,compress=zstd:3,subvol=@snapshots   0      0
UUID=${BTRFS_UUID}                         /var/log      btrfs    defaults,compress=zstd:3,subvol=@log         0      0
FSTAB

# --- Generate crypttab ---
cat > "${MNT}/tmp/crypttab" <<CRYPTTAB
# /etc/crypttab — LogOS Gentoo
cryptroot UUID=${CRYPT_UUID} none luks,discard
CRYPTTAB

# --- Generate GRUB defaults ---
cat > "${MNT}/tmp/grub-default" <<GRUB
# /etc/default/grub — LogOS Gentoo
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="LogOS"
GRUB_CMDLINE_LINUX="rd.luks.uuid=${CRYPT_UUID} rd.luks.name=${CRYPT_UUID}=cryptroot root=UUID=${BTRFS_UUID} rootflags=subvol=@ rootfstype=btrfs"
GRUB_CMDLINE_LINUX_DEFAULT=""
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --speed=115200"
GRUB
log "Configs deployed"

# --- Generate dracut config ---
cat > "${MNT}/tmp/dracut-logos.conf" <<DRACUT
# /etc/dracut.conf.d/logos.conf — LUKS + Btrfs + systemd
add_dracutmodules+=" crypt dm rootfs-block btrfs "
add_dracutmodules+=" systemd systemd-initrd systemd-cryptsetup "
install_items+=" /etc/crypttab "
hostonly="no"
DRACUT

log "Configs deployed"

# ---------------------------------------------------------------------------
# STEP 8: Chroot build
# ---------------------------------------------------------------------------
step 8 "Chroot build"

# Mount virtual filesystems (Gentoo Handbook)
mount --types proc /proc "${MNT}/proc"
mount --rbind /sys "${MNT}/sys"
mount --make-rslave "${MNT}/sys"
mount --rbind /dev "${MNT}/dev"
mount --make-rslave "${MNT}/dev"
mount --bind /run "${MNT}/run"
mount --make-slave "${MNT}/run"

# Run chroot script — all output captured to log
cat > "${MNT}/tmp/chroot-build.sh" <<'CHROOT_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

# Explicit PATH — ensures grub-mkconfig etc. are found
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
source /etc/profile

log()  { echo "[CHROOT $(date +%H:%M:%S)] $*"; }
die()  { log "FATAL: $*"; exit 1; }

# ---- Portage sync ----
log "Running emerge-webrsync"
emerge-webrsync || die "emerge-webrsync failed"
log "Running emerge --sync"
emerge --sync || true   # may fail on first run, non-fatal

# ---- Handle glibc masking ----
# The stage3 may ship a glibc version that's since been masked in the repo.
# Unmask it so @world and kernel installs don't fail.
log "Checking for masked glibc"
INSTALLED_GLIBC="$(qatom -F '%{CATEGORY}/%{PN}-%{PV}' "$(portageq best_version / sys-libs/glibc)" 2>/dev/null || true)"
if [[ -n "${INSTALLED_GLIBC}" ]]; then
    if ! emerge --pretend --oneshot sys-libs/glibc >/dev/null 2>&1; then
        log "glibc ${INSTALLED_GLIBC} is masked — unmasking"
        mkdir -p /etc/portage/package.unmask
        echo "${INSTALLED_GLIBC}" > /etc/portage/package.unmask/glibc
        log "glibc unmasked"
    fi
fi

# ---- Set profile ----
# Phase A: plain systemd profile (no desktop — avoids pulling in GTK/Qt/KDE/GNOME)
log "Setting profile"
PROFILE="$(eselect profile list | grep -P 'default/linux/amd64/23\.0/systemd\b' | grep -v 'desktop\|merged-usr' | grep -oP '\[\d+\]' | head -1 | tr -d '[]')"
if [[ -n "${PROFILE}" ]]; then
    eselect profile set "${PROFILE}"
    log "Profile set to default/linux/amd64/23.0/systemd"
else
    die "Cannot find systemd profile"
fi

# ---- @world update ----
log "Updating @world"
emerge --update --deep --changed-use --with-bdeps=y @world || {
    log "World update failed — trying with --backtrack=50"
    emerge --update --deep --changed-use --with-bdeps=y --backtrack=50 @world || {
        log "WARNING: @world update failed, continuing with package installs"
    }
}

# ---- Timezone + locale ----
log "Setting timezone and locale"
echo "UTC" > /etc/timezone
emerge --config sys-libs/timezone-data 2>/dev/null || ln -sf /usr/share/zoneinfo/UTC /etc/localtime

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
eselect locale set en_US.utf8 2>/dev/null || eselect locale set C.utf8 2>/dev/null || true
env-update
source /etc/profile

# ---- Hostname ----
echo "logos" > /etc/hostname

# ---- Deploy generated configs ----
log "Deploying fstab, crypttab, dracut config"
cp /tmp/fstab /etc/fstab
cp /tmp/crypttab /etc/crypttab
mkdir -p /etc/dracut.conf.d
cp /tmp/dracut-logos.conf /etc/dracut.conf.d/logos.conf
mkdir -p /etc/default
cp /tmp/grub-default /etc/default/grub

# ---- Install dracut prerequisites ----
# btrfs-progs and cryptsetup MUST be installed before the kernel.
# The kernel postinst runs dracut, and dracut needs the 'btrfs' and
# 'cryptsetup' commands to include those modules in the initramfs.
log "Installing dracut prerequisites (btrfs-progs, cryptsetup)"
emerge sys-fs/btrfs-progs sys-fs/cryptsetup || die "btrfs-progs/cryptsetup install failed"

# ---- Install kernel ----
log "Installing linux-firmware"
emerge sys-kernel/linux-firmware || die "linux-firmware install failed"

log "Installing installkernel"
emerge sys-kernel/installkernel || die "installkernel install failed"

log "Installing gentoo-kernel-bin"
if ! emerge sys-kernel/gentoo-kernel-bin; then
    log "gentoo-kernel-bin failed, trying gentoo-kernel (source)"
    emerge sys-kernel/gentoo-kernel || die "kernel install failed"
fi

# ---- Verify kernel ----
KVER="$(ls /lib/modules/ | sort -V | tail -1)"
[[ -n "${KVER}" ]] || die "No kernel modules found in /lib/modules/"
log "Kernel version: ${KVER}"

KIMG="$(find /boot -maxdepth 1 -name 'vmlinuz-*' -o -name 'kernel-*' | head -1)"
[[ -n "${KIMG}" ]] || die "No kernel image found in /boot"
log "Kernel image: ${KIMG}"

# ---- Rebuild initramfs (with crypttab) ----
log "Rebuilding initramfs with dracut"
dracut --force --kver "${KVER}" || die "dracut failed"

INITRD="$(find /boot -maxdepth 1 -name 'initramfs-*' -o -name 'initrd-*' | head -1)"
[[ -n "${INITRD}" ]] || die "No initramfs found in /boot after dracut"
log "Initramfs: ${INITRD}"

# ---- Install GRUB ----
log "Installing GRUB"
emerge sys-boot/grub || die "grub install failed"

grub-install --target=x86_64-efi --efi-directory=/boot/efi --removable \
    || die "grub-install failed"

grub-mkconfig -o /boot/grub/grub.cfg || die "grub-mkconfig failed"
log "GRUB installed and configured"

# ---- Networking (systemd-networkd) ----
log "Configuring networking"
mkdir -p /etc/systemd/network
cat > /etc/systemd/network/20-wired.network <<NET
[Match]
Name=en*

[Network]
DHCP=yes
NET

systemctl enable systemd-networkd.service
systemctl enable systemd-resolved.service

# ---- Users ----
log "Creating users"
echo "root:@ROOT_PASS@" | chpasswd
useradd -m -G wheel -s /bin/bash "@USER_NAME@"
echo "@USER_NAME@:@USER_PASS@" | chpasswd

# ---- Serial console for QEMU testing ----
log "Enabling serial console"
systemctl enable serial-getty@ttyS0.service

# ---- Success sentinel ----
log "BUILD_OK"
CHROOT_SCRIPT

# Substitute variables that can't use heredoc quoting
sed -i "s/@ROOT_PASS@/${ROOT_PASS}/g" "${MNT}/tmp/chroot-build.sh"
sed -i "s/@USER_NAME@/${USER_NAME}/g" "${MNT}/tmp/chroot-build.sh"
sed -i "s/@USER_PASS@/${USER_PASS}/g" "${MNT}/tmp/chroot-build.sh"

chmod +x "${MNT}/tmp/chroot-build.sh"

log "Entering chroot (log: ${CHROOT_LOG})"
chroot "${MNT}" /tmp/chroot-build.sh 2>&1 | tee "${CHROOT_LOG}"

# Check for success sentinel
if ! grep -q "BUILD_OK" "${CHROOT_LOG}"; then
    die "Chroot build failed — check ${CHROOT_LOG}"
fi

log "Chroot build completed successfully"

# ---------------------------------------------------------------------------
# STEP 9: Unmount + convert to qcow2
# ---------------------------------------------------------------------------
step 9 "Unmount + convert"

# Unmount virtual filesystems first
umount -l "${MNT}/run" 2>/dev/null || true
umount -l "${MNT}/dev/pts" 2>/dev/null || true
umount -l "${MNT}/dev" 2>/dev/null || true
umount -l "${MNT}/sys" 2>/dev/null || true
umount -l "${MNT}/proc" 2>/dev/null || true

# Unmount data filesystems
umount "${MNT}/boot/efi"
umount "${MNT}/boot"
umount "${MNT}/home"
umount "${MNT}/var/log"
umount "${MNT}/.snapshots"
umount "${MNT}"

# Close LUKS
cryptsetup close "${LUKS_NAME}"

# Detach loop device
losetup -d "${LOOP_DEV}"
unset LOOP_DEV  # Prevent cleanup trap from double-detaching

log "All filesystems unmounted"

# Convert raw → qcow2 (compressed)
log "Converting to qcow2 (this may take a few minutes)"
qemu-img convert -f raw -O qcow2 -c "${IMG_RAW}" "${IMG_QCOW2}" \
    || die "qcow2 conversion failed"

log "qcow2 image: ${IMG_QCOW2}"
ls -lh "${IMG_QCOW2}"

# Optionally remove raw image to save space
rm -f "${IMG_RAW}"
log "Raw image removed"

# ---------------------------------------------------------------------------
# STEP 10: Boot test
# ---------------------------------------------------------------------------
step 10 "Boot test"

# Find OVMF firmware
OVMF=""
for f in /usr/share/edk2-ovmf/OVMF_CODE.fd \
         /usr/share/OVMF/OVMF_CODE.fd \
         /usr/share/ovmf/OVMF_CODE.fd \
         /usr/share/qemu/OVMF_CODE.fd; do
    [[ -f "$f" ]] && OVMF="$f" && break
done
[[ -n "${OVMF}" ]] || die "OVMF firmware not found — install sys-firmware/edk2-ovmf"

log "Booting VM with QEMU (serial console)"
log "  Login user: ${USER_NAME}"
log "  Exit: Ctrl-A X"
log ""

qemu-system-x86_64 \
    -m 4G \
    -smp 2 \
    -enable-kvm \
    -drive if=pflash,format=raw,readonly=on,file="${OVMF}" \
    -drive file="${IMG_QCOW2}",format=qcow2,if=virtio \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -device virtio-net-pci,netdev=net0 \
    -nographic \
    -serial mon:stdio
