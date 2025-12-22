#!/bin/bash

################################################################################
# LogOS Installer - Module 00: Pre-Flight Checks
# Validates system requirements and installation environment
################################################################################

module_00_preflight() {
    log_step "00" "Pre-Flight Checks"

    # Check running as root
    if [[ $EUID -ne 0 ]]; then
        log_fatal "This installer must be run as root"
        exit 1
    fi

    # Check for Arch Linux live environment
    if [[ ! -f /etc/arch-release ]]; then
        log_fatal "Not running from Arch Linux live environment"
        exit 1
    fi

    if [[ ! -d /run/archiso ]]; then
        log_warn "Not detected as Arch ISO environment (may be running in installed system)"
    fi

    # Check UEFI mode
    log_info "Checking UEFI mode..."
    if [[ ! -d /sys/firmware/efi/efivars ]]; then
        log_fatal "System is not booted in UEFI mode. Legacy BIOS is not supported."
        exit 1
    fi
    log_success "UEFI mode confirmed"

    # Check network connectivity
    log_info "Checking network connectivity..."
    if ! ping -c 3 archlinux.org &>/dev/null; then
        log_error "No network connectivity detected"
        log_info "Please configure network:"
        log_info "  Wired: dhcpcd"
        log_info "  WiFi:  iwctl"
        exit 1
    fi
    log_success "Network connectivity confirmed"

    # Check internet speed (basic)
    log_info "Testing download speed..."
    if timeout 10 curl -o /dev/null https://archlinux.org &>/dev/null; then
        log_success "Internet connection appears healthy"
    else
        log_warn "Slow internet connection detected. Installation may take longer."
    fi

    # Sync system clock
    log_info "Synchronizing system clock..."
    timedatectl set-ntp true
    sleep 2
    log_success "System clock synchronized"

    # Check available RAM
    local ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    log_info "Available RAM: ${ram_mb}MB"
    if [[ $ram_mb -lt 2048 ]]; then
        log_warn "Low RAM detected (${ram_mb}MB). Minimum 4GB recommended."
        confirm_or_exit "Continue anyway?"
    elif [[ $ram_mb -lt 4096 ]]; then
        log_warn "RAM below recommended (${ram_mb}MB). 8GB+ recommended for best experience."
    else
        log_success "RAM: ${ram_mb}MB (sufficient)"
    fi

    # Check CPU cores
    local cores=$(nproc)
    log_info "CPU cores: $cores"
    if [[ $cores -lt 2 ]]; then
        log_warn "Single-core CPU detected. Multi-core recommended."
    else
        log_success "CPU cores: $cores"
    fi

    # Check required commands
    log_info "Checking required commands..."
    local required_cmds=(
        "pacstrap"
        "arch-chroot"
        "parted"
        "mkfs.fat"
        "mkfs.ext4"
        "mkfs.btrfs"
        "cryptsetup"
        "grub-install"
    )

    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            log_fatal "Required command not found: $cmd"
            exit 1
        fi
    done
    log_success "All required commands present"

    # Check for existing installations
    log_info "Checking for existing installations..."
    if mountpoint -q /mnt 2>/dev/null; then
        log_warn "/mnt is already mounted. This may indicate a previous installation attempt."
        confirm_destructive "Unmount /mnt and continue?"
        umount -R /mnt || log_fatal "Failed to unmount /mnt"
    fi

    # Check for cryptsetup mappings
    if [[ -b /dev/mapper/cryptroot ]]; then
        log_warn "Encrypted partition 'cryptroot' already open"
        confirm_destructive "Close existing encrypted partition?"
        cryptsetup close cryptroot || log_fatal "Failed to close cryptroot"
    fi

    # Update package databases
    log_info "Updating package databases..."
    if pacman -Sy --noconfirm &>/dev/null; then
        log_success "Package databases updated"
    else
        log_error "Failed to update package databases"
        log_info "Trying to refresh keyring..."
        pacman -S --noconfirm archlinux-keyring &>/dev/null || true
        pacman -Sy --noconfirm &>/dev/null || log_fatal "Cannot update package databases"
    fi

    # Optimize mirrors
    log_info "Optimizing mirror list..."
    if ! command -v reflector &>/dev/null; then
        log_info "Installing reflector..."
        pacman -S --noconfirm reflector &>/dev/null
    fi

    reflector --country US,Canada,Germany,UK --age 12 --protocol https \
        --sort rate --save /etc/pacman.d/mirrorlist &>/dev/null || log_warn "Mirror optimization failed"
    log_success "Mirrors optimized"

    # Log system information
    log_system_info

    log_success "Pre-flight checks completed"
}

# Export function
export -f module_00_preflight
