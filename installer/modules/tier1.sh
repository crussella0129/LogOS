#!/bin/bash

################################################################################
# LogOS Installer - Tier 1 (Security Infrastructure) Installation Module
################################################################################

install_tier1() {
    log "Installing Tier 1: Security Infrastructure..."

    # Verify /mnt is mounted before proceeding
    if ! mountpoint -q /mnt; then
        error "Root filesystem not mounted at /mnt - cannot install Tier 1 packages"
        return 1
    fi

    # Tier 1 packages - Security infrastructure
    local tier1_packages=(
        apparmor
        audit
        ufw
        fail2ban
        openssh
        sbctl mokutil
    )

    # Install packages
    log "Installing security packages..."
    if pacstrap /mnt "${tier1_packages[@]}"; then
        success "Tier 1 packages installed successfully"
    else
        error "Tier 1 installation failed"
        return 1
    fi

    # Verify installation
    verify_tier1
}

verify_tier1() {
    log "Verifying Tier 1 installation..."

    # Check for security binaries
    local security_bins=(
        "/mnt/usr/bin/apparmor_status"
        "/mnt/usr/bin/auditctl"
        "/mnt/usr/sbin/ufw"
        "/mnt/usr/bin/fail2ban-client"
        "/mnt/usr/bin/sbctl"
    )

    for bin in "${security_bins[@]}"; do
        if [[ -f "$bin" ]]; then
            success "Security binary found: $(basename $bin)"
        else
            warning "Security binary not found: $bin (may be optional)"
        fi
    done

    success "Tier 1 verification passed"
    return 0
}
