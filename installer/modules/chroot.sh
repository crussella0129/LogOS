#!/bin/bash

################################################################################
# LogOS Installer - Chroot Configuration Module
################################################################################

configure_system_chroot() {
    log "Entering chroot for system configuration..."

    # Set timezone
    configure_timezone

    # Set locale
    configure_locale

    # Set hostname
    configure_hostname

    # Configure OS branding
    configure_os_branding

    # Configure users
    configure_users

    # Configure security
    configure_security

    # Configure services
    configure_services

    # Configure zram
    configure_zram

    # Configure mkinitcpio
    configure_mkinitcpio

    success "Chroot configuration completed"
}

configure_timezone() {
    log "Setting timezone to $TIMEZONE..."
    arch_chroot "ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime"
    arch_chroot "hwclock --systohc"
    success "Timezone configured"
}

configure_locale() {
    log "Configuring locale: $LOCALE..."

    # Enable locale
    arch_chroot "sed -i 's/#${LOCALE}/${LOCALE}/' /etc/locale.gen"
    arch_chroot "locale-gen"

    # Set system locale
    echo "LANG=$LOCALE" > /mnt/etc/locale.conf
    echo "KEYMAP=$KEYMAP" > /mnt/etc/vconsole.conf

    success "Locale configured"
}

configure_hostname() {
    log "Setting hostname: $HOSTNAME..."

    echo "$HOSTNAME" > /mnt/etc/hostname

    # Configure hosts file
    cat > /mnt/etc/hosts <<EOF
127.0.0.1    localhost
::1          localhost
127.0.1.1    ${HOSTNAME}.localdomain $HOSTNAME
EOF

    success "Hostname configured"
}

configure_os_branding() {
    log "Configuring LogOS branding..."

    # Install /etc/os-release
    if [[ -f "${SCRIPT_DIR}/templates/os-release.template" ]]; then
        cp "${SCRIPT_DIR}/templates/os-release.template" /mnt/etc/os-release
        success "/etc/os-release installed"
    else
        warning "os-release template not found, using default"
    fi

    # Install /etc/issue (console login banner)
    if [[ -f "${SCRIPT_DIR}/templates/issue.template" ]]; then
        cp "${SCRIPT_DIR}/templates/issue.template" /mnt/etc/issue
        success "/etc/issue installed"
    else
        warning "issue template not found, using default"
    fi

    # Configure bash prompt with LogOS branding
    cat > /mnt/etc/profile.d/logos-prompt.sh <<'EOF'
# LogOS bash prompt configuration
if [ -n "$BASH_VERSION" ]; then
    # Set PS1 to show "LogOS:" prefix
    PS1='LogOS: \u@\h:\w\$ '
fi
EOF
    chmod +x /mnt/etc/profile.d/logos-prompt.sh
    success "LogOS prompt configured"

    success "LogOS branding configured"
}

configure_users() {
    log "Configuring users..."

    # Set root password
    echo "root:$ROOT_PASS" | arch_chroot "chpasswd"
    success "Root password set"

    # Create user
    arch_chroot "useradd -m -G wheel,audio,video,optical,storage,power,network -s /bin/bash $USERNAME"
    echo "${USERNAME}:$USER_PASS" | arch_chroot "chpasswd"
    success "User $USERNAME created"

    # Configure sudo
    echo "%wheel ALL=(ALL:ALL) ALL" > /mnt/etc/sudoers.d/wheel
    chmod 440 /mnt/etc/sudoers.d/wheel
    success "Sudo configured"

    # Fix subvolume ownership
    arch_chroot "mkdir -p /home/$USERNAME/{Documents,Sync}"
    arch_chroot "chown -R $USERNAME:$USERNAME /home/$USERNAME"
    success "User directories configured"
}

configure_security() {
    log "Configuring security infrastructure..."

    # Enable services
    enable_services apparmor auditd ufw fail2ban sshd

    # Configure audit rules
    cat > /mnt/etc/audit/rules.d/logos-audit.rules <<'EOF'
# Delete all existing rules
-D
# Set buffer size
-b 8192
# Failure mode: 1 = printk
-f 1
# Monitor identity files
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d -p wa -k sudoers
# Monitor command execution
-a always,exit -F arch=b64 -S execve -k exec
# Make rules immutable (requires reboot to change)
-e 2
EOF

    # Configure UFW
    cat > /mnt/etc/ufw/ufw.conf <<'EOF'
ENABLED=yes
LOGLEVEL=low
EOF

    # Configure fail2ban
    cat > /mnt/etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
ignoreip = 127.0.0.1/8 ::1
banaction = ufw
backend = systemd

[sshd]
enabled = true
maxretry = 3
bantime = 86400
EOF

    # Harden SSH
    cat > /mnt/etc/ssh/sshd_config.d/10-logos.conf <<'EOF'
# Protocol
Protocol 2

# Authentication
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
AuthenticationMethods any
MaxAuthTries 3

# Security
X11Forwarding no
AllowTcpForwarding no
ClientAliveInterval 300
ClientAliveCountMax 2

# Performance
UseDNS no
EOF

    # Kernel hardening (sysctl)
    cat > /mnt/etc/sysctl.d/99-logos-security.conf <<'EOF'
# Network hardening
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.all.log_martians = 1

# Kernel hardening
kernel.randomize_va_space = 2
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.perf_event_paranoid = 3
kernel.yama.ptrace_scope = 2

# Filesystem hardening
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.suid_dumpable = 0
EOF

    success "Security configuration completed"
}

configure_services() {
    log "Enabling core services..."

    # Network
    enable_service NetworkManager

    success "Core services enabled"
}

configure_zram() {
    log "Configuring zram swap..."

    # Install zram-generator
    arch_chroot "pacman -S --noconfirm zram-generator"

    # Configure zram
    cat > /mnt/etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF

    success "zram configured"
}

configure_mkinitcpio() {
    log "Configuring mkinitcpio for encryption..."

    # Define the required hooks for LUKS encryption with Btrfs
    local required_hooks="HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt btrfs filesystems fsck)"

    # Backup original mkinitcpio.conf
    cp /mnt/etc/mkinitcpio.conf /mnt/etc/mkinitcpio.conf.bak

    # Update HOOKS for encryption support
    # Use a more robust pattern that handles any HOOKS line format
    if grep -q "^HOOKS=" /mnt/etc/mkinitcpio.conf; then
        sed -i "s/^HOOKS=.*/$required_hooks/" /mnt/etc/mkinitcpio.conf
        log "Updated existing HOOKS line"
    elif grep -q "^#.*HOOKS=" /mnt/etc/mkinitcpio.conf; then
        # If HOOKS is commented out, add our own line
        echo "$required_hooks" >> /mnt/etc/mkinitcpio.conf
        log "Added new HOOKS line (original was commented)"
    else
        # No HOOKS line found at all, add one
        echo "$required_hooks" >> /mnt/etc/mkinitcpio.conf
        log "Added new HOOKS line"
    fi

    # Verify the HOOKS line contains 'encrypt' hook
    if ! grep -q "^HOOKS=.*encrypt.*" /mnt/etc/mkinitcpio.conf; then
        error "CRITICAL: Failed to configure encrypt hook in mkinitcpio.conf"
        log "Current mkinitcpio.conf HOOKS line:"
        grep "HOOKS=" /mnt/etc/mkinitcpio.conf | tee -a "$INSTALL_LOG"
        return 1
    fi

    # Also verify btrfs hook is present
    if ! grep -q "^HOOKS=.*btrfs.*" /mnt/etc/mkinitcpio.conf; then
        error "CRITICAL: Failed to configure btrfs hook in mkinitcpio.conf"
        return 1
    fi

    success "mkinitcpio.conf updated with encrypt and btrfs hooks"

    # Display the configured HOOKS line for verification
    log "Configured HOOKS:"
    grep "^HOOKS=" /mnt/etc/mkinitcpio.conf | tee -a "$INSTALL_LOG"

    # Regenerate initramfs for all kernels
    log "Regenerating initramfs for all installed kernels..."
    if ! arch_chroot "mkinitcpio -P" 2>&1 | tee -a "$INSTALL_LOG"; then
        error "Failed to regenerate initramfs"
        return 1
    fi

    # Verify initramfs files were created/updated
    log "Verifying initramfs files..."
    local initramfs_found=0
    for kernel in linux linux-lts linux-zen; do
        if [[ -f "/mnt/boot/initramfs-${kernel}.img" ]]; then
            success "Initramfs found: initramfs-${kernel}.img"
            initramfs_found=$((initramfs_found + 1))
        fi
    done

    if [[ $initramfs_found -eq 0 ]]; then
        error "CRITICAL: No initramfs files found after mkinitcpio"
        return 1
    fi

    success "mkinitcpio configured and $initramfs_found initramfs image(s) generated"
}
