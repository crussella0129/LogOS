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

    # Update HOOKS for encryption support
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt btrfs filesystems fsck)/' \
        /mnt/etc/mkinitcpio.conf

    # Regenerate initramfs for all kernels
    arch_chroot "mkinitcpio -P"

    success "mkinitcpio configured and initramfs generated"
}
