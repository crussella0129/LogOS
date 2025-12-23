#!/bin/bash

################################################################################
# LogOS Automated Installer
# Version: 2025.7
# Description: Complete automated installation of LogOS Operating System
################################################################################

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source library files
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/validation.sh"

# Global variables
INSTALL_LOG="/tmp/logos-install.log"
CONFIG_FILE="/tmp/logos-config.env"

################################################################################
# Main Installation Function
################################################################################

main() {
    clear
    print_banner

    # Check if running in live environment
    if ! check_live_environment; then
        error "This script must be run from an Arch Linux live environment"
        exit 1
    fi

    log "LogOS Installation Started"

    # Phase 1: Pre-flight checks and user input
    print_section "Phase 1: Pre-Flight Checks"
    check_uefi_mode
    check_network_connectivity
    sync_time
    optimize_mirrors

    # Phase 2: Gather configuration
    print_section "Phase 2: Configuration"
    gather_user_input
    confirm_installation

    # Phase 3: Disk preparation
    print_section "Phase 3: Disk Preparation"
    source "${SCRIPT_DIR}/modules/partitioning.sh"
    prepare_disk
    create_partitions
    setup_encryption
    mount_filesystems

    # Phase 4: Base system installation
    print_section "Phase 4: Tier 0 - Boot Critical Installation"
    source "${SCRIPT_DIR}/modules/tier0.sh"
    install_tier0

    # Phase 5: Security infrastructure
    print_section "Phase 5: Tier 1 - Security Infrastructure"
    source "${SCRIPT_DIR}/modules/tier1.sh"
    install_tier1

    # Phase 6: System configuration
    print_section "Phase 6: System Configuration"
    generate_fstab
    source "${SCRIPT_DIR}/modules/chroot.sh"
    configure_system_chroot

    # Phase 7: Bootloader
    print_section "Phase 7: Bootloader Installation"
    source "${SCRIPT_DIR}/modules/bootloader.sh"
    install_bootloader
    create_ringed_city_profiles

    # Phase 8: Post-installation
    print_section "Phase 8: Finalization"
    finalize_installation

    # Installation complete
    print_success
}

################################################################################
# Banner
################################################################################

print_banner() {
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║                          LogOS Automated Installer                           ║
║                    Ontology Substrate Operating System                       ║
║                                                                              ║
║                              Version 2025.7                                  ║
║                           Codename: Ringed City                              ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝

EOF

    echo -e "${YELLOW}WARNING: This will ERASE ALL DATA on the selected disk!${NC}"
    echo ""
    echo "Press ENTER to continue, or Ctrl+C to abort..."
    read
}

################################################################################
# Pre-Flight Checks
################################################################################

check_live_environment() {
    [[ -f /etc/arch-release ]] && [[ -d /run/archiso ]]
}

check_uefi_mode() {
    log "Checking UEFI mode..."
    if [[ ! -d /sys/firmware/efi/efivars ]]; then
        error "System is not booted in UEFI mode. Legacy BIOS is not supported."
        exit 1
    fi
    success "UEFI mode confirmed"
}

check_network_connectivity() {
    log "Checking network connectivity..."
    if ! ping -c 3 archlinux.org &>/dev/null; then
        error "No network connectivity. Please configure network and try again."
        info "For WiFi, use: iwctl"
        exit 1
    fi
    success "Network connectivity confirmed"
}

sync_time() {
    log "Synchronizing system time..."
    timedatectl set-ntp true
    sleep 2
    success "System time synchronized"
}

optimize_mirrors() {
    log "Optimizing mirror list..."
    pacman -Sy --noconfirm &>/dev/null
    pacman -S --noconfirm reflector &>/dev/null
    reflector --country US,Canada,Germany,UK --age 12 --protocol https \
        --sort rate --save /etc/pacman.d/mirrorlist &>/dev/null
    success "Mirrors optimized"
}

################################################################################
# User Input
################################################################################

gather_user_input() {
    log "Gathering user configuration..."

    # Load config if exists
    [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

    # Target disk
    echo ""
    echo "Available disks:"
    lsblk -d -o NAME,SIZE,TYPE | grep disk
    echo ""
    read -p "Enter target disk (e.g., sda, nvme0n1): " DISK
    export DISK="/dev/${DISK}"
    validate_disk "$DISK" || exit 1

    # Hostname
    read -p "Enter hostname [logos]: " HOSTNAME
    export HOSTNAME="${HOSTNAME:-logos}"

    # Username
    read -p "Enter username [logos]: " USERNAME
    export USERNAME="${USERNAME:-logos}"

    # Timezone
    read -p "Enter timezone (e.g., America/New_York) [America/New_York]: " TIMEZONE
    export TIMEZONE="${TIMEZONE:-America/New_York}"

    # Locale
    read -p "Enter locale [en_US.UTF-8]: " LOCALE
    export LOCALE="${LOCALE:-en_US.UTF-8}"

    # Keyboard layout
    read -p "Enter keyboard layout [us]: " KEYMAP
    export KEYMAP="${KEYMAP:-us}"

    # LUKS passphrase
    while true; do
        read -s -p "Enter LUKS encryption passphrase (min 20 chars): " LUKS_PASS
        echo ""
        if [[ ${#LUKS_PASS} -lt 20 ]]; then
            error "Passphrase must be at least 20 characters"
            continue
        fi
        read -s -p "Confirm LUKS passphrase: " LUKS_PASS_CONFIRM
        echo ""
        if [[ "$LUKS_PASS" == "$LUKS_PASS_CONFIRM" ]]; then
            export LUKS_PASS
            break
        else
            error "Passphrases do not match"
        fi
    done

    # Root password
    while true; do
        read -s -p "Enter root password: " ROOT_PASS
        echo ""
        read -s -p "Confirm root password: " ROOT_PASS_CONFIRM
        echo ""
        if [[ "$ROOT_PASS" == "$ROOT_PASS_CONFIRM" ]]; then
            export ROOT_PASS
            break
        else
            error "Passwords do not match"
        fi
    done

    # User password
    while true; do
        read -s -p "Enter user password: " USER_PASS
        echo ""
        read -s -p "Confirm user password: " USER_PASS_CONFIRM
        echo ""
        if [[ "$USER_PASS" == "$USER_PASS_CONFIRM" ]]; then
            export USER_PASS
            break
        else
            error "Passwords do not match"
        fi
    done

    # GPU selection
    echo ""
    echo "Select GPU type:"
    echo "1) AMD (Recommended)"
    echo "2) NVIDIA"
    echo "3) Intel"
    echo "4) None/Integrated"
    read -p "Enter choice [1]: " GPU_CHOICE
    case "${GPU_CHOICE:-1}" in
        1) export GPU_TYPE="amd" ;;
        2) export GPU_TYPE="nvidia" ;;
        3) export GPU_TYPE="intel" ;;
        4) export GPU_TYPE="none" ;;
        *) export GPU_TYPE="amd" ;;
    esac

    # Desktop Environment
    echo ""
    echo "Select Desktop Environment:"
    echo "1) GNOME (Recommended for workstations)"
    echo "2) KDE Plasma (Power users/Gaming)"
    echo "3) XFCE (Lightweight)"
    echo "4) i3-wm (Tiling)"
    echo "5) None (Server/Minimal)"
    read -p "Enter choice [1]: " DE_CHOICE
    case "${DE_CHOICE:-1}" in
        1) export DESKTOP_ENV="gnome" ;;
        2) export DESKTOP_ENV="kde" ;;
        3) export DESKTOP_ENV="xfce" ;;
        4) export DESKTOP_ENV="i3" ;;
        5) export DESKTOP_ENV="none" ;;
        *) export DESKTOP_ENV="gnome" ;;
    esac

    # Secure Boot
    echo ""
    read -p "Configure Secure Boot with sbctl? (y/N): " SECURE_BOOT
    export SECURE_BOOT="${SECURE_BOOT:-n}"

    # Save configuration
    save_config

    success "Configuration gathered"
}

save_config() {
    cat > "$CONFIG_FILE" <<EOF
DISK="$DISK"
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
TIMEZONE="$TIMEZONE"
LOCALE="$LOCALE"
KEYMAP="$KEYMAP"
GPU_TYPE="$GPU_TYPE"
DESKTOP_ENV="$DESKTOP_ENV"
SECURE_BOOT="$SECURE_BOOT"
EOF
}

confirm_installation() {
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "Installation Configuration Summary:"
    echo "═══════════════════════════════════════════════════════════"
    echo "Target Disk:         $DISK"
    echo "Hostname:            $HOSTNAME"
    echo "Username:            $USERNAME"
    echo "Timezone:            $TIMEZONE"
    echo "Locale:              $LOCALE"
    echo "Keyboard:            $KEYMAP"
    echo "GPU:                 $GPU_TYPE"
    echo "Desktop:             $DESKTOP_ENV"
    echo "Secure Boot:         $SECURE_BOOT"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo -e "${RED}WARNING: ALL DATA ON $DISK WILL BE ERASED!${NC}"
    echo ""
    read -p "Type 'YES' in capital letters to proceed: " CONFIRM
    if [[ "$CONFIRM" != "YES" ]]; then
        error "Installation aborted by user"
        exit 1
    fi
}

################################################################################
# Finalization
################################################################################

finalize_installation() {
    log "Finalizing installation..."

    # Unmount filesystems
    umount -R /mnt || true
    cryptsetup close cryptroot || true

    success "Installation finalized"
}

print_success() {
    clear
    cat << 'EOF'

╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║                     LogOS Installation Complete!                             ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝

Next Steps:
1. IMPORTANT: Remove the installation media (USB/ISO) from your system
2. Reboot: systemctl reboot
3. Your system should automatically boot into LogOS (GRUB bootloader)
4. Select your desired boot profile at the GRUB menu:
   - Gael (Maximum Security)
   - Midir (Balanced) - Recommended for daily use
   - Halflight (Performance)

5. After first boot, run post-installation setup:
   - Install Tier 2 (Desktop): ./installer/modules/tier2-standalone.sh
   - Install Tier 3 (Specialized): ./installer/modules/tier3-standalone.sh

If the system boots back to the installation media instead of LogOS:
- Check your BIOS/UEFI boot order settings
- Ensure "LogOS" is set as the first boot option
- Disable boot from USB/CD in BIOS if needed

Documentation: See LogOS_Build_Guide_2025_MASTER_v7.md

EOF

    log "Installation completed successfully"
}

# Start installation
main "$@"
