#!/bin/bash

################################################################################
# LogOS Installer - Validation Functions Library
################################################################################

################################################################################
# Disk Validation
################################################################################

validate_disk() {
    local disk=$1

    # Check if disk exists
    if [[ ! -b "$disk" ]]; then
        error "Disk $disk does not exist"
        return 1
    fi

    # Check if disk is mounted
    if mount | grep -q "^$disk"; then
        error "Disk $disk is currently mounted"
        return 1
    fi

    # Check disk size
    local size_bytes=$(lsblk -b -n -o SIZE "$disk" | head -1)
    local size_gb=$(( size_bytes / 1024 / 1024 / 1024 ))

    if [[ $size_gb -lt 80 ]]; then
        error "Disk $disk is too small (${size_gb}GB). Minimum 80GB required."
        return 1
    fi

    success "Disk $disk validated (${size_gb}GB)"
    return 0
}

################################################################################
# Password Validation
################################################################################

validate_password_strength() {
    local password=$1
    local min_length=${2:-12}

    if [[ ${#password} -lt $min_length ]]; then
        error "Password must be at least $min_length characters"
        return 1
    fi

    return 0
}

################################################################################
# Hostname Validation
################################################################################

validate_hostname() {
    local hostname=$1

    # Check hostname format
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
        error "Invalid hostname format"
        return 1
    fi

    return 0
}

################################################################################
# Username Validation
################################################################################

validate_username() {
    local username=$1

    # Check username format
    if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        error "Invalid username format (lowercase letters, numbers, underscore, hyphen only)"
        return 1
    fi

    # Check username length
    if [[ ${#username} -gt 32 ]]; then
        error "Username too long (max 32 characters)"
        return 1
    fi

    return 0
}

################################################################################
# Timezone Validation
################################################################################

validate_timezone() {
    local timezone=$1

    if [[ ! -f "/usr/share/zoneinfo/$timezone" ]]; then
        error "Invalid timezone: $timezone"
        return 1
    fi

    return 0
}

################################################################################
# Locale Validation
################################################################################

validate_locale() {
    local locale=$1

    # Check if locale is in common format
    if [[ ! "$locale" =~ ^[a-z]{2}_[A-Z]{2}\. ]]; then
        warning "Locale format may be invalid: $locale"
        return 1
    fi

    return 0
}

################################################################################
# LUKS Passphrase Validation
################################################################################

validate_luks_passphrase() {
    local passphrase=$1

    # Minimum length
    if [[ ${#passphrase} -lt 20 ]]; then
        error "LUKS passphrase must be at least 20 characters"
        return 1
    fi

    # Check for common weak patterns
    if [[ "$passphrase" =~ ^(.)\1+$ ]]; then
        error "Passphrase cannot be repeated characters"
        return 1
    fi

    if [[ "$passphrase" =~ ^[0-9]+$ ]]; then
        warning "Passphrase contains only numbers - consider adding letters"
    fi

    return 0
}

################################################################################
# Network Validation
################################################################################

validate_network() {
    # Check for network interface
    if ! ip link show | grep -q "state UP"; then
        error "No active network interface found"
        return 1
    fi

    # Check for internet connectivity
    if ! ping -c 1 archlinux.org &>/dev/null; then
        error "No internet connectivity"
        return 1
    fi

    return 0
}

################################################################################
# UEFI Validation
################################################################################

validate_uefi() {
    if [[ ! -d /sys/firmware/efi/efivars ]]; then
        error "System is not booted in UEFI mode"
        return 1
    fi

    return 0
}

################################################################################
# Partition Validation
################################################################################

validate_partition_scheme() {
    local disk=$1

    # Check if partitions exist
    get_partition_names "$disk"

    if [[ ! -b "$EFI_PART" ]] || [[ ! -b "$BOOT_PART" ]] || [[ ! -b "$ROOT_PART" ]]; then
        error "Partition scheme validation failed"
        return 1
    fi

    return 0
}

################################################################################
# System Requirements
################################################################################

validate_system_requirements() {
    log "Validating system requirements..."

    # Check RAM
    local ram_gb=$(get_total_ram)
    if [[ $ram_gb -lt 4 ]]; then
        warning "System has less than 4GB RAM. Some features may not work optimally."
    else
        success "RAM: ${ram_gb}GB"
    fi

    # Check CPU cores
    local cores=$(get_cpu_cores)
    if [[ $cores -lt 2 ]]; then
        warning "System has only $cores CPU core(s). Minimum 2 cores recommended."
    else
        success "CPU cores: $cores"
    fi

    # Check UEFI
    validate_uefi || return 1

    # Check network
    validate_network || return 1

    success "System requirements validated"
    return 0
}

################################################################################
# Installation Environment Validation
################################################################################

validate_install_environment() {
    log "Validating installation environment..."

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        return 1
    fi

    # Check if running from Arch ISO
    if [[ ! -f /etc/arch-release ]]; then
        error "Not running from Arch Linux"
        return 1
    fi

    # Check for required commands
    local required_cmds="pacstrap arch-chroot mkfs.ext4 mkfs.fat mkfs.btrfs cryptsetup"
    for cmd in $required_cmds; do
        if ! command -v "$cmd" &>/dev/null; then
            error "Required command not found: $cmd"
            return 1
        fi
    done

    success "Installation environment validated"
    return 0
}
