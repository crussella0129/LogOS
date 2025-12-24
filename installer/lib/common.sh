#!/bin/bash

################################################################################
# LogOS Installer - Common Functions Library
################################################################################

# Colors
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m' # No Color

################################################################################
# Logging Functions
################################################################################

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$INSTALL_LOG"
}

info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

success() {
    echo -e "${GREEN}✓${NC} $*" | tee -a "$INSTALL_LOG"
}

error() {
    echo -e "${RED}✗ ERROR:${NC} $*" | tee -a "$INSTALL_LOG" >&2
}

warning() {
    echo -e "${YELLOW}⚠ WARNING:${NC} $*"
}

print_section() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

################################################################################
# Error Handling
################################################################################

handle_error() {
    local line_no=$1
    error "Installation failed at line $line_no"
    error "Check log file: $INSTALL_LOG"

    # Attempt cleanup
    cleanup_on_error

    exit 1
}

trap 'handle_error ${LINENO}' ERR

cleanup_on_error() {
    log "Performing emergency cleanup..."

    # Unmount filesystems
    umount -R /mnt 2>/dev/null || true

    # Close cryptsetup
    cryptsetup close cryptroot 2>/dev/null || true

    warning "Partial installation may exist. Manual cleanup may be required."
}

################################################################################
# Progress Indicators
################################################################################

show_progress() {
    local message="$1"
    local cmd="$2"

    echo -n "$message... "
    if eval "$cmd" &>/dev/null; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi
}

spinner() {
    local pid=$1
    local message=$2
    local spin='|/-\\'
    local i=0
    local spin_len=${#spin}

    echo -n "$message "
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) % spin_len ))
        printf "\r$message ${spin:$i:1}"
        sleep 0.1
    done
    printf "\r$message ${GREEN}✓${NC}\n"
}

################################################################################
# Partition Detection Functions
################################################################################

get_partition_names() {
    local disk=$1

    # Detect disk type and set partition naming scheme
    if [[ "$disk" =~ nvme ]]; then
        export EFI_PART="${disk}p1"
        export BOOT_PART="${disk}p2"
        export ROOT_PART="${disk}p3"
    else
        export EFI_PART="${disk}1"
        export BOOT_PART="${disk}2"
        export ROOT_PART="${disk}3"
    fi
}

################################################################################
# Chroot Execution
################################################################################

arch_chroot() {
    arch-chroot /mnt /bin/bash -c "$*"
}

################################################################################
# Package Installation Helpers
################################################################################

install_packages() {
    local packages="$*"
    log "Installing packages: $packages"

    if pacstrap -K /mnt $packages; then
        success "Packages installed"
        return 0
    else
        error "Package installation failed"
        return 1
    fi
}

chroot_install_packages() {
    local packages="$*"
    log "Installing packages in chroot: $packages"

    arch_chroot "pacman -S --noconfirm $packages"
}

################################################################################
# Service Management
################################################################################

enable_service() {
    local service=$1
    log "Enabling service: $service"
    arch_chroot "systemctl enable $service"
}

enable_services() {
    local services="$*"
    for service in $services; do
        enable_service "$service"
    done
}

################################################################################
# File Creation Helpers
################################################################################

create_file() {
    local filepath=$1
    local content=$2

    echo "$content" > "$filepath"
}

create_chroot_file() {
    local filepath=$1
    local content=$2

    echo "$content" > "/mnt$filepath"
}

################################################################################
# UUID Retrieval
################################################################################

get_uuid() {
    local device=$1
    blkid -s UUID -o value "$device"
}

get_luks_uuid() {
    # Find the LUKS encrypted partition
    for part in "$ROOT_PART"; do
        if blkid "$part" | grep -q crypto_LUKS; then
            get_uuid "$part"
            return 0
        fi
    done

    error "Could not find LUKS partition"
    return 1
}

get_btrfs_uuid() {
    get_uuid /dev/mapper/cryptroot
}

################################################################################
# Interactive Prompts
################################################################################

confirm() {
    local prompt=$1
    local response

    read -p "$prompt (y/N): " response
    [[ "$response" =~ ^[Yy]$ ]]
}

ask_yes_no() {
    local prompt=$1
    local default=${2:-n}

    if [[ "$default" == "y" ]]; then
        read -p "$prompt (Y/n): " response
        response=${response:-y}
    else
        read -p "$prompt (y/N): " response
        response=${response:-n}
    fi

    [[ "$response" =~ ^[Yy]$ ]]
}

################################################################################
# Validation Helpers
################################################################################

is_mounted() {
    local mountpoint=$1
    mountpoint -q "$mountpoint"
}

device_exists() {
    local device=$1
    [[ -b "$device" ]]
}

################################################################################
# System Information
################################################################################

get_total_ram() {
    free -g | awk '/^Mem:/{print $2}'
}

get_cpu_cores() {
    nproc
}

is_laptop() {
    [[ -d /sys/class/power_supply/BAT0 ]] || [[ -d /sys/class/power_supply/BAT1 ]]
}

################################################################################
# Retry Logic
################################################################################

retry() {
    local max_attempts=$1
    shift
    local cmd="$*"
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if eval "$cmd"; then
            return 0
        fi
        warning "Attempt $attempt/$max_attempts failed. Retrying..."
        ((attempt++))
        sleep 2
    done

    error "Command failed after $max_attempts attempts: $cmd"
    return 1
}

################################################################################
# Disk Space Helpers
################################################################################

get_available_space() {
    local device=$1
    lsblk -b -n -o SIZE "$device" | head -1
}

bytes_to_gb() {
    local bytes=$1
    echo $(( bytes / 1024 / 1024 / 1024 ))
}

################################################################################
# Exit Handler
################################################################################

cleanup_on_exit() {
    log "Cleaning up temporary files..."
    rm -f /tmp/logos-*.tmp 2>/dev/null || true
}

trap cleanup_on_exit EXIT

