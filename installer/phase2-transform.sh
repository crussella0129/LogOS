#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root."
  exit 1
fi

log() { echo "[phase2] $*"; }
install_pkgs() { pacman -S --noconfirm --needed "$@"; }

log "Installing kernel trio"
install_pkgs linux linux-headers linux-lts linux-lts-headers linux-zen linux-zen-headers
if [[ "${ENABLE_HARDENED:-0}" == "1" ]]; then
  install_pkgs linux-hardened linux-hardened-headers
fi

log "Installing security services"
install_pkgs apparmor audit
systemctl enable apparmor.service
systemctl enable auditd.service

log "Capturing UUIDs"
if [[ -n "${CRYPT_UUID_OVERRIDE:-}" ]]; then
  CRYPT_UUID="${CRYPT_UUID_OVERRIDE}"
else
  crypt_dev="$(blkid -t TYPE=crypto_LUKS -o device | head -n1 || true)"
  if [[ -z "${crypt_dev}" ]]; then
    echo "Unable to locate crypto_LUKS device. Set CRYPT_UUID_OVERRIDE." >&2
    exit 1
  fi
  CRYPT_UUID="$(blkid -s UUID -o value "${crypt_dev}")"
fi

if [[ -n "${BTRFS_UUID_OVERRIDE:-}" ]]; then
  BTRFS_UUID="${BTRFS_UUID_OVERRIDE}"
else
  root_dev="$(findmnt -n -o SOURCE / || true)"
  if [[ -n "${root_dev}" ]]; then
    BTRFS_UUID="$(blkid -s UUID -o value "${root_dev}" || true)"
  else
    BTRFS_UUID=""
  fi
  if [[ -z "${BTRFS_UUID}" ]]; then
    btrfs_dev="$(blkid -t TYPE=btrfs -o device | head -n1 || true)"
    if [[ -z "${btrfs_dev}" ]]; then
      echo "Unable to locate btrfs UUID. Set BTRFS_UUID_OVERRIDE." >&2
      exit 1
    fi
    BTRFS_UUID="$(blkid -s UUID -o value "${btrfs_dev}")"
  fi
fi

printf '%s\n' "${CRYPT_UUID}" > /tmp/crypt_uuid
printf '%s\n' "${BTRFS_UUID}" > /tmp/btrfs_uuid

log "Configuring mkinitcpio"
cat > /etc/mkinitcpio.conf << 'EOF'
# LogOS mkinitcpio configuration

MODULES=(btrfs)

BINARIES=()

FILES=()

# encrypt must come before filesystems
HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt btrfs filesystems fsck)

COMPRESSION="zstd"
COMPRESSION_OPTIONS=(-9 -T0)
EOF

mkinitcpio -P

log "Installing CPU microcode"
if grep -q "GenuineIntel" /proc/cpuinfo; then
  install_pkgs intel-ucode
elif grep -q "AuthenticAMD" /proc/cpuinfo; then
  install_pkgs amd-ucode
fi

log "Writing GRUB defaults"
cat > /etc/default/grub << 'EOF'
# LogOS GRUB configuration
GRUB_DEFAULT=saved
GRUB_SAVEDEFAULT=true
GRUB_TIMEOUT=10
GRUB_DISTRIBUTOR="LogOS"
GRUB_CMDLINE_LINUX_DEFAULT=""
GRUB_CMDLINE_LINUX=""
GRUB_ENABLE_CRYPTODISK=y
GRUB_DISABLE_OS_PROBER=false
GRUB_GFXMODE=auto
GRUB_GFXPAYLOAD_LINUX=keep
GRUB_TERMINAL_OUTPUT=gfxterm
EOF

CRYPT_UUID_NO_DASH="${CRYPT_UUID//-/}"

log "Creating Ringed City GRUB profiles"
cat > /etc/grub.d/41_logos_profiles << EOF
#!/bin/bash
# LogOS Ringed City security profiles

menuentry "LogOS - Gael [Maximum Security]" --class logos --class gnu-linux --class gnu --class os \$menuentry_id_option 'logos-gael' {
    load_video
    set gfxpayload=keep
    insmod gzio
    insmod part_gpt
    insmod btrfs
    insmod cryptodisk
    insmod luks2
    cryptomount -u ${CRYPT_UUID_NO_DASH}
    search --no-floppy --fs-uuid --set=root ${BTRFS_UUID}
    echo 'Loading Linux LTS with Maximum Security...'
    linux /@/boot/vmlinuz-linux-lts root=UUID=${BTRFS_UUID} rootflags=subvol=@ rw cryptdevice=UUID=${CRYPT_UUID}:cryptroot audit=1 apparmor=1 lsm=landlock,lockdown,yama,integrity,apparmor,bpf lockdown=confidentiality mitigations=auto,nosmt nosmt=force init_on_alloc=1 init_on_free=1 slab_nomerge pti=on quiet loglevel=3
    echo 'Loading initial ramdisk...'
    initrd /@/boot/initramfs-linux-lts.img
}

menuentry "LogOS - Midir [Daily Driver]" --class logos --class gnu-linux --class gnu --class os \$menuentry_id_option 'logos-midir' {
    load_video
    set gfxpayload=keep
    insmod gzio
    insmod part_gpt
    insmod btrfs
    insmod cryptodisk
    insmod luks2
    cryptomount -u ${CRYPT_UUID_NO_DASH}
    search --no-floppy --fs-uuid --set=root ${BTRFS_UUID}
    echo 'Loading Linux Zen - Daily Driver...'
    linux /@/boot/vmlinuz-linux-zen root=UUID=${BTRFS_UUID} rootflags=subvol=@ rw cryptdevice=UUID=${CRYPT_UUID}:cryptroot audit=1 apparmor=1 lsm=landlock,lockdown,yama,integrity,apparmor,bpf mitigations=auto quiet loglevel=3
    echo 'Loading initial ramdisk...'
    initrd /@/boot/initramfs-linux-zen.img
}

menuentry "LogOS - Halflight [Performance]" --class logos --class gnu-linux --class gnu --class os \$menuentry_id_option 'logos-halflight' {
    load_video
    set gfxpayload=keep
    insmod gzio
    insmod part_gpt
    insmod btrfs
    insmod cryptodisk
    insmod luks2
    cryptomount -u ${CRYPT_UUID_NO_DASH}
    search --no-floppy --fs-uuid --set=root ${BTRFS_UUID}
    echo 'Loading Linux Zen - Performance Mode...'
    linux /@/boot/vmlinuz-linux-zen root=UUID=${BTRFS_UUID} rootflags=subvol=@ rw cryptdevice=UUID=${CRYPT_UUID}:cryptroot audit=0 mitigations=off nowatchdog nmi_watchdog=0 quiet loglevel=3
    echo 'Loading initial ramdisk...'
    initrd /@/boot/initramfs-linux-zen.img
}

submenu "LogOS Recovery Options" --class recovery {
    menuentry "Linux LTS - Fallback Initramfs" --class recovery {
        load_video
        insmod gzio
        insmod part_gpt
        insmod btrfs
        insmod cryptodisk
        insmod luks2
        cryptomount -u ${CRYPT_UUID_NO_DASH}
        search --no-floppy --fs-uuid --set=root ${BTRFS_UUID}
        linux /@/boot/vmlinuz-linux-lts root=UUID=${BTRFS_UUID} rootflags=subvol=@ rw cryptdevice=UUID=${CRYPT_UUID}:cryptroot
        initrd /@/boot/initramfs-linux-lts-fallback.img
    }

    menuentry "Linux (Mainline) - Fallback" --class recovery {
        load_video
        insmod gzio
        insmod part_gpt
        insmod btrfs
        insmod cryptodisk
        insmod luks2
        cryptomount -u ${CRYPT_UUID_NO_DASH}
        search --no-floppy --fs-uuid --set=root ${BTRFS_UUID}
        linux /@/boot/vmlinuz-linux root=UUID=${BTRFS_UUID} rootflags=subvol=@ rw cryptdevice=UUID=${CRYPT_UUID}:cryptroot
        initrd /@/boot/initramfs-linux-fallback.img
    }
}
EOF

chmod +x /etc/grub.d/41_logos_profiles
chmod -x /etc/grub.d/10_linux || true

grub-mkconfig -o /boot/grub/grub.cfg

log "Applying sysctl hardening"
cat > /etc/sysctl.d/99-logos-hardening.conf << 'EOF'
# LogOS kernel hardening
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.perf_event_paranoid = 3
kernel.sysrq = 0
kernel.unprivileged_bpf_disabled = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.icmp_echo_ignore_all = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
EOF

log "Configuring firewall"
install_pkgs ufw
systemctl enable ufw.service
ufw default deny incoming
ufw default allow outgoing
ufw --force enable

log "Installing core utilities"
install_pkgs btrfs-progs snapper snap-pac grub-btrfs htop btop neofetch fastfetch tree wget curl rsync openssh tmux zsh man-db man-pages texinfo

systemctl enable NetworkManager.service
systemctl enable grub-btrfsd.service

log "Writing LogOS branding"
cat > /etc/logos-release << 'EOF'
NAME="LogOS"
VERSION="2025.8"
CODENAME="Ringed City"
BASE="Arch Linux"
ARCHITECTURE="x86_64"
INSTALLATION_METHOD="archinstall"
EOF

cat > /etc/motd << 'EOF'
Ontology Substrate OS - Ringed City Build
Profiles: Gael (Security) | Midir (Balanced) | Halflight (Performance)
"Knowledge preserved. Reason applied. Civilization continued."
EOF

log "Phase 2 complete. Reboot when ready."
