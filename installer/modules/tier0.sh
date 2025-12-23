#!/bin/bash

################################################################################
# LogOS Installer - Tier 0 (Boot-Critical) Installation Module
################################################################################

install_tier0() {
    log "Installing Tier 0: Boot-Critical packages..."

    # Tier 0 packages - ONLY what's needed to boot
    local tier0_packages=(
        base
        linux linux-firmware linux-headers
        linux-lts linux-lts-headers
        linux-zen linux-zen-headers
        grub efibootmgr
        intel-ucode amd-ucode
        btrfs-progs cryptsetup
        sudo
        networkmanager
        man-db man-pages
        nano vim
    )

    # Create essential configuration files BEFORE pacstrap
    # (mkinitcpio hooks read these during kernel package installation)
    log "Creating pre-installation configuration files..."

    # Verify /mnt is mounted before proceeding
    if ! mountpoint -q /mnt; then
        error "Root filesystem not mounted at /mnt - cannot create pre-installation configs"
        return 1
    fi

    # Ensure target root skeleton exists (pacstrap normally creates /mnt/etc)
    if ! mkdir -p /mnt/etc; then
        error "Failed to create /mnt/etc directory"
        log "Mount status:"
        mount | grep /mnt | tee -a "$INSTALL_LOG"
        return 1
    fi

    # Verify directory was created
    if [[ ! -d /mnt/etc ]]; then
        error "/mnt/etc directory does not exist after mkdir"
        return 1
    fi

    # Create vconsole.conf (required by mkinitcpio sd-vconsole hook)
    if ! cat > /mnt/etc/vconsole.conf <<EOF
KEYMAP=${KEYMAP:-us}
EOF
    then
        error "Failed to create /mnt/etc/vconsole.conf"
        return 1
    fi

    # Create locale.conf
    if ! cat > /mnt/etc/locale.conf <<EOF
LANG=${LOCALE:-en_US.UTF-8}
EOF
    then
        error "Failed to create /mnt/etc/locale.conf"
        return 1
    fi

    success "Pre-installation configuration created"

    # Install packages
    log "Running pacstrap with Tier 0 packages..."
    echo "This may take several minutes depending on your internet connection..."

    if pacstrap -K /mnt "${tier0_packages[@]}"; then
        success "Tier 0 packages installed successfully"
    else
        error "Tier 0 installation failed"
        return 1
    fi

    # (Optional but recommended) Ensure the files still exist after pacstrap
    # in case anything overwrote /mnt/etc during base install.
    if [[ ! -f /mnt/etc/vconsole.conf ]]; then
        warning "vconsole.conf missing after pacstrap; recreating"
        echo "KEYMAP=${KEYMAP:-us}" > /mnt/etc/vconsole.conf
    fi
    if [[ ! -f /mnt/etc/locale.conf ]]; then
        warning "locale.conf missing after pacstrap; recreating"
        echo "LANG=${LOCALE:-en_US.UTF-8}" > /mnt/etc/locale.conf
    fi

    # Verify kernels installed
    verify_tier0
}

verify_tier0() {
    log "Verifying Tier 0 installation..."

    # Check for kernels
    local kernels_found=0
    for kernel in linux linux-lts linux-zen; do
        if [[ -f "/mnt/boot/vmlinuz-$kernel" ]]; then
            success "Kernel found: $kernel"
            ((kernels_found++))
        else
            warning "Kernel not found: $kernel"
        fi
    done

    if [[ $kernels_found -lt 3 ]]; then
        error "Not all kernels were installed"
        return 1
    fi

    # Check for essential binaries
    local essential_bins=(
        "/mnt/usr/bin/btrfs"
        "/mnt/usr/bin/cryptsetup"
        "/mnt/usr/bin/sudo"
        "/mnt/usr/bin/nano"
    )

    for bin in "${essential_bins[@]}"; do
        if [[ -f "$bin" ]]; then
            success "Essential binary found: $(basename "$bin")"
        else
            error "Essential binary not found: $bin"
            return 1
        fi
    done

    success "Tier 0 verification passed"
    return 0
}
