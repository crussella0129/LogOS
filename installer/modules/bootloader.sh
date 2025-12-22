#!/bin/bash

################################################################################
# LogOS Installer - Bootloader Configuration Module
################################################################################

install_bootloader() {
    log "Installing GRUB bootloader..."

    # Get UUIDs
    local crypt_uuid=$(get_luks_uuid)
    local btrfs_uuid=$(get_btrfs_uuid)
    local boot_uuid=$(get_uuid "$BOOT_PART")

    log "LUKS UUID: $crypt_uuid"
    log "Btrfs UUID: $btrfs_uuid"
    log "Boot UUID: $boot_uuid"

    # Save UUIDs for boot profile creation
    echo "$boot_uuid" > /mnt/tmp/boot_uuid
    echo "$crypt_uuid" > /mnt/tmp/crypt_uuid
    echo "$btrfs_uuid" > /mnt/tmp/btrfs_uuid

    # Configure GRUB defaults
    cat > /mnt/etc/default/grub <<EOF
# GRUB defaults for LogOS
GRUB_DEFAULT=saved
GRUB_SAVEDEFAULT=true
GRUB_TIMEOUT=10
GRUB_DISTRIBUTOR="LogOS"
GRUB_CMDLINE_LINUX_DEFAULT=""
GRUB_CMDLINE_LINUX="cryptdevice=UUID=$crypt_uuid:cryptroot root=/dev/mapper/cryptroot"
GRUB_ENABLE_CRYPTODISK=y
GRUB_DISABLE_OS_PROBER=false
GRUB_GFXMODE=auto
GRUB_GFXPAYLOAD_LINUX=keep
EOF

    success "GRUB configuration created"

    # Install GRUB
    log "Installing GRUB to EFI partition..."
    arch_chroot "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=LogOS --recheck"

    success "GRUB installed"
}

create_ringed_city_profiles() {
    log "Creating Ringed City boot profiles..."

    # Read UUIDs from saved files
    local boot_uuid=$(cat /mnt/tmp/boot_uuid)
    local crypt_uuid=$(cat /mnt/tmp/crypt_uuid)

    # Create custom GRUB menu
    cat > /mnt/etc/grub.d/41_logos_profiles <<ENDOFFILE
#!/bin/bash
cat << 'MENUEOF'
# ============================================
# LOGOS — RINGED CITY SECURITY PROFILES
# Kernel set: linux-lts, linux, linux-zen
# ============================================

# --------------------------------------------
# GAEL — Maximum Security
# Kernel: linux-lts
# Mitigations: full + nosmt + lockdown
# --------------------------------------------
menuentry "LogOS — Gael (Maximum Security)" --class arch --class gnu-linux --class gnu --class os {
    load_video
    set gfxpayload=keep
    insmod gzio
    insmod part_gpt
    insmod ext2
    search --no-floppy --fs-uuid --set=root $boot_uuid

    echo 'Loading linux-lts (Gael profile)...'
    linux  /vmlinuz-linux-lts \\
        cryptdevice=UUID=$crypt_uuid:cryptroot \\
        root=/dev/mapper/cryptroot \\
        rootflags=subvol=@ rw \\
        audit=1 apparmor=1 \\
        lsm=landlock,lockdown,yama,integrity,apparmor,bpf \\
        mitigations=auto,nosmt \\
        lockdown=confidentiality \\
        quiet
    initrd /intel-ucode.img /amd-ucode.img /initramfs-linux-lts.img
}

# --------------------------------------------
# MIDIR — Balanced Daily Driver
# Kernel: linux-zen
# Mitigations: auto
# --------------------------------------------
menuentry "LogOS — Midir (Balanced)" --class arch --class gnu-linux --class gnu --class os {
    load_video
    set gfxpayload=keep
    insmod gzio
    insmod part_gpt
    insmod ext2
    search --no-floppy --fs-uuid --set=root $boot_uuid

    echo 'Loading linux-zen (Midir profile)...'
    linux  /vmlinuz-linux-zen \\
        cryptdevice=UUID=$crypt_uuid:cryptroot \\
        root=/dev/mapper/cryptroot \\
        rootflags=subvol=@ rw \\
        audit=1 apparmor=1 \\
        lsm=landlock,lockdown,yama,integrity,apparmor,bpf \\
        mitigations=auto \\
        quiet
    initrd /intel-ucode.img /amd-ucode.img /initramfs-linux-zen.img
}

# --------------------------------------------
# HALFLIGHT — Performance Focus
# Kernel: linux-zen
# Mitigations: off
# --------------------------------------------
menuentry "LogOS — Halflight (Performance)" --class arch --class gnu-linux --class gnu --class os {
    load_video
    set gfxpayload=keep
    insmod gzio
    insmod part_gpt
    insmod ext2
    search --no-floppy --fs-uuid --set=root $boot_uuid

    echo 'Loading linux-zen (Halflight profile)...'
    linux  /vmlinuz-linux-zen \\
        cryptdevice=UUID=$crypt_uuid:cryptroot \\
        root=/dev/mapper/cryptroot \\
        rootflags=subvol=@ rw \\
        audit=1 apparmor=1 \\
        lsm=landlock,lockdown,yama,integrity,apparmor,bpf \\
        mitigations=off \\
        quiet
    initrd /intel-ucode.img /amd-ucode.img /initramfs-linux-zen.img
}

# --------------------------------------------
# FALLBACK — Stock linux kernel
# --------------------------------------------
menuentry "LogOS — Fallback (linux)" --class arch --class gnu-linux --class gnu --class os {
    load_video
    set gfxpayload=keep
    insmod gzio
    insmod part_gpt
    insmod ext2
    search --no-floppy --fs-uuid --set=root $boot_uuid

    echo 'Loading linux (fallback)...'
    linux  /vmlinuz-linux \\
        cryptdevice=UUID=$crypt_uuid:cryptroot \\
        root=/dev/mapper/cryptroot \\
        rootflags=subvol=@ rw \\
        audit=1 apparmor=1 \\
        lsm=landlock,lockdown,yama,integrity,apparmor,bpf \\
        mitigations=auto \\
        quiet
    initrd /intel-ucode.img /amd-ucode.img /initramfs-linux.img
}
MENUEOF
ENDOFFILE

    # Make executable
    arch_chroot "chmod +x /etc/grub.d/41_logos_profiles"

    success "Ringed City profiles created"

    # Generate GRUB configuration
    log "Generating GRUB configuration..."
    arch_chroot "grub-mkconfig -o /boot/grub/grub.cfg"

    success "GRUB configuration generated"

    # Verify
    log "Verifying GRUB installation..."
    if [[ -f /mnt/boot/efi/EFI/LogOS/grubx64.efi ]]; then
        success "GRUB bootloader verified"
    else
        error "GRUB bootloader not found"
        return 1
    fi

    # Verify boot profiles
    if grep -q "Gael" /mnt/boot/grub/grub.cfg && \
       grep -q "Midir" /mnt/boot/grub/grub.cfg && \
       grep -q "Halflight" /mnt/boot/grub/grub.cfg; then
        success "Ringed City profiles verified in GRUB config"
    else
        warning "Some boot profiles may be missing from GRUB config"
    fi
}

configure_secure_boot() {
    if [[ "${SECURE_BOOT,,}" == "y" ]]; then
        log "Configuring Secure Boot with sbctl..."

        warning "Secure Boot configuration requires additional manual steps after first boot:"
        info "1. Boot into BIOS/UEFI"
        info "2. Reset Secure Boot to Setup Mode"
        info "3. Boot into LogOS"
        info "4. Run: sudo sbctl create-keys"
        info "5. Run: sudo sbctl enroll-keys --microsoft"
        info "6. Run: sudo sbctl sign -s /boot/efi/EFI/LogOS/grubx64.efi"
        info "7. Run: sudo sbctl sign -s /boot/vmlinuz-linux*"
        info "8. Reboot and enable Secure Boot in BIOS"

        # Create pacman hook for auto-signing (in chroot)
        cat > /mnt/etc/pacman.d/hooks/99-secureboot.hook <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux
Target = linux-lts
Target = linux-zen
Target = linux-hardened

[Action]
Description = Signing kernel with SecureBoot keys
When = PostTransaction
Exec = /usr/bin/find /boot -maxdepth 1 -name 'vmlinuz-*' -exec /usr/bin/sh -c 'if ! /usr/bin/sbctl verify {} 2>/dev/null; then /usr/bin/sbctl sign -s {}; fi' ;
Depends = sbctl
EOF

        success "Secure Boot hook created"
    else
        info "Secure Boot configuration skipped"
    fi
}
