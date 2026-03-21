#!/usr/bin/env bash
# 04-bootloader.sh — GRUB + Ringed City Profiles
# Context: Run inside artix-chroot /mnt, after 03-chroot-setup.sh.
# Installs GRUB, writes the Ringed City boot profile script, and
# generates the GRUB configuration with baked-in LUKS/Btrfs UUIDs.
#
# Ported from: phase2-transform.sh:83-186 (GRUB config + profiles — primary source)

LOGOS_SECTION="04-boot"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f /root/LogOS/lib/common.sh ]]; then
  source /root/LogOS/lib/common.sh
  source /root/LogOS/lib/detect.sh
  load_config /root/LogOS/logos.conf
else
  source "${SCRIPT_DIR}/../lib/common.sh"
  source "${SCRIPT_DIR}/../lib/detect.sh"
  load_config "${SCRIPT_DIR}/../logos.conf"
fi

require_root
require_chroot

# ── Detect UUIDs ───────────────────────────────────────────────────
log "Detecting disk UUIDs"
CRYPT_UUID="$(detect_crypt_uuid)"
BTRFS_UUID="$(detect_btrfs_uuid)"
CRYPT_UUID_NO_DASH="${CRYPT_UUID//-/}"

log_ok "LUKS UUID:  ${CRYPT_UUID}"
log_ok "Btrfs UUID: ${BTRFS_UUID}"

# ── Write GRUB defaults ───────────────────────────────────────────
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
log_ok "GRUB defaults written"

# ── Install GRUB ──────────────────────────────────────────────────
log "Installing GRUB to EFI"
grub-install --target=x86_64-efi \
  --efi-directory=/boot/efi \
  --bootloader-id=LogOS
log_ok "GRUB installed"

# ── Write Ringed City profiles ─────────────────────────────────────
log "Creating Ringed City GRUB profiles"

# The heredoc is NOT quoted — variables expand at write time to bake in UUIDs.
cat > /etc/grub.d/41_logos_profiles << EOF
#!/bin/bash
# LogOS Ringed City security profiles
# UUIDs baked at install time — regenerate with grub-mkconfig if disks change.

EOF

# ── Gael [Maximum Security] ────────────────────────────────────────
if [[ "${LOGOS_PROFILE_GAEL:-1}" == "1" ]]; then
  cat >> /etc/grub.d/41_logos_profiles << EOF
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

EOF
fi

# ── Midir [Daily Driver] ──────────────────────────────────────────
if [[ "${LOGOS_PROFILE_MIDIR:-1}" == "1" ]]; then
  cat >> /etc/grub.d/41_logos_profiles << EOF
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

EOF
fi

# ── Halflight [Performance] ───────────────────────────────────────
if [[ "${LOGOS_PROFILE_HALFLIGHT:-1}" == "1" ]]; then
  cat >> /etc/grub.d/41_logos_profiles << EOF
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

EOF
fi

# ── Recovery submenu ──────────────────────────────────────────────
cat >> /etc/grub.d/41_logos_profiles << EOF
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

# ── Disable default 10_linux (our profiles replace it) ─────────────
chmod -x /etc/grub.d/10_linux || true

# ── Generate GRUB config ──────────────────────────────────────────
log "Generating GRUB configuration"
grub-mkconfig -o /boot/grub/grub.cfg
log_ok "GRUB configured with Ringed City profiles"

log_ok "Bootloader setup complete. Proceed to 05-security.sh"
