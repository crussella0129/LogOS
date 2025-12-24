#!/bin/bash

################################################################################
# LogOS Installer - Bootloader Configuration Module
################################################################################

setup_efi_boot_entry() {
    log "Configuring EFI boot entry..."

    # Get the disk device (not partition) for efibootmgr
    local efi_disk
    if [[ "$DISK" =~ nvme ]]; then
        efi_disk="$DISK"
        local efi_part_num="1"
    else
        efi_disk="$DISK"
        local efi_part_num="1"
    fi

    # Check if LogOS boot entry exists
    log "Checking for existing LogOS boot entry..."
    local boot_entries
    boot_entries=$(arch_chroot "efibootmgr")

    if echo "$boot_entries" | grep -q "LogOS"; then
        success "LogOS boot entry found"
        # Get the boot number
        local boot_num=$(echo "$boot_entries" | grep "LogOS" | sed 's/Boot\([0-9A-F]\{4\}\).*/\1/')
        log "LogOS boot entry: Boot$boot_num"
    else
        warning "LogOS boot entry not found, creating manually..."
        # Create boot entry manually
        arch_chroot "efibootmgr --create --disk $efi_disk --part $efi_part_num --label 'LogOS' --loader '\EFI\LogOS\grubx64.efi'"
        success "LogOS boot entry created"
        boot_entries=$(arch_chroot "efibootmgr")
        boot_num=$(echo "$boot_entries" | grep "LogOS" | sed 's/Boot\([0-9A-F]\{4\}\).*/\1/')
    fi

    # Set LogOS as first boot option
    log "Setting LogOS as first boot option..."
    local current_order=$(echo "$boot_entries" | grep "BootOrder:" | sed 's/BootOrder: //')

    # Remove LogOS from current order if it exists and prepend it
    local new_order="$boot_num"
    for entry in ${current_order//,/ }; do
        if [[ "$entry" != "$boot_num" ]]; then
            new_order="$new_order,$entry"
        fi
    done

    arch_chroot "efibootmgr --bootorder $new_order"
    success "Boot order updated: LogOS is now the first boot option"

    # Display final boot configuration
    log "Final EFI boot configuration:"
    arch_chroot "efibootmgr" | tee -a "$INSTALL_LOG"
}

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

    # Install LogOS boot branding
    install_grub_branding

    # Configure GRUB defaults
    cat > /mnt/etc/default/grub <<EOF
# GRUB defaults for LogOS
GRUB_DEFAULT=saved
GRUB_SAVEDEFAULT=true
GRUB_TIMEOUT=10
GRUB_DISTRIBUTOR="Arch"
GRUB_CMDLINE_LINUX_DEFAULT=""
GRUB_CMDLINE_LINUX="cryptdevice=UUID=$crypt_uuid:cryptroot root=/dev/mapper/cryptroot"
GRUB_ENABLE_CRYPTODISK=y
GRUB_DISABLE_OS_PROBER=false
GRUB_GFXMODE=1920x1080,1024x768,auto
GRUB_GFXPAYLOAD_LINUX=keep
GRUB_BACKGROUND="/boot/grub/themes/logos/logos-boot.png"
GRUB_THEME="/boot/grub/themes/logos/theme.txt"
EOF

    success "GRUB configuration created"

    # Install GRUB
    log "Installing GRUB to EFI partition..."
    arch_chroot "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=LogOS --recheck"

    success "GRUB installed"

    # Verify and fix EFI boot entry
    setup_efi_boot_entry

    # Optional Secure Boot configuration
    configure_secure_boot
}

install_grub_branding() {
    log "Installing LogOS boot branding..."

    # Create GRUB theme directory
    mkdir -p /mnt/boot/grub/themes/logos

    # Copy boot splash image from installer assets
    if [[ -f "${SCRIPT_DIR}/assets/branding/logos-boot.png" ]]; then
        cp "${SCRIPT_DIR}/assets/branding/logos-boot.png" /mnt/boot/grub/themes/logos/
        success "Boot splash image installed"
    else
        warning "Boot splash image not found in installer assets"
    fi

    # Create GRUB theme configuration
    cat > /mnt/boot/grub/themes/logos/theme.txt <<'EOF'
# LogOS GRUB Theme
# Based on the Ringed City architecture

# Boot menu appearance
desktop-image: "logos-boot.png"
title-text: ""
terminal-font: "Terminus Regular 16"

# Colors (Dark theme with LogOS branding)
terminal-box: "terminal_box_*.png"
+ boot_menu {
  left = 15%
  top = 30%
  width = 70%
  height = 50%
  item_color = "#a0a0a0"
  selected_item_color = "#00bfff"
  item_height = 32
  item_padding = 8
  item_spacing = 4
}

+ label {
  top = 85%
  left = 0
  width = 100%
  height = 20
  text = "LogOS - Ontology Substrate Operating System"
  color = "#cccccc"
  align = "center"
}
EOF

    success "GRUB theme configured"
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
        mkdir -p /mnt/etc/pacman.d/hooks
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
