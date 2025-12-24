#!/bin/bash

################################################################################
# LogOS Installation Orchestrator
# Main entry point for automated LogOS installation
# Version: 2025.7 - Ringed City
################################################################################

set -euo pipefail

################################################################################
# Script Initialization
################################################################################

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR

# Source core libraries
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/error-handling.sh"
source "${SCRIPT_DIR}/lib/validation.sh"

# Initialize logging
init_logging

# Register error handlers
register_cleanup default_cleanup

# Start time
START_TIME=$(date +%s)

################################################################################
# Configuration
################################################################################

# Installation configuration file
CONFIG_FILE="/tmp/logos-install.conf"

# Total installation steps
TOTAL_STEPS=9

################################################################################
# Banner
################################################################################

print_banner() {
    clear
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║                          LogOS Installation System                           ║
║                    Ontology Substrate Operating System                       ║
║                                                                              ║
║                              Version 2025.7                                  ║
║                           Codename: Ringed City                              ║
║                                                                              ║
║   "In the beginning was the Logos, and the Logos was with God..."           ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝

EOF

    echo -e "${YELLOW}⚠ WARNING: This will ERASE ALL DATA on the selected disk! ⚠${NC}"
    echo ""
    echo "This installer will guide you through installing LogOS, a hardened"
    echo "Arch Linux-based system with:"
    echo ""
    echo "  - Triple-kernel architecture (Gael/Midir/Halflight profiles)"
    echo "  - Full-disk encryption with LUKS2"
    echo "  - Btrfs with snapshots and rollback capability"
    echo "  - AppArmor, audit, UFW, fail2ban security"
    echo "  - Knowledge preservation topology (Cold Canon/Warm Mesh)"
    echo "  - Professional branding and boot experience"
    echo ""
    echo "Installation time: 15-30 minutes (depending on internet speed)"
    echo ""
    read -p "Press ENTER to begin installation, or Ctrl+C to exit... "
}

################################################################################
# Module Loading
################################################################################

load_modules() {
    log_info "Loading installation modules..."

    # Load modules in order
    local modules=(
        "00-preflight.sh"
        "partitioning.sh"
        "tier0.sh"
        "tier1.sh"
        "chroot.sh"
        "bootloader.sh"
        "60-desktop.sh"
    )

    for module in "${modules[@]}"; do
        local module_path="${SCRIPT_DIR}/modules/${module}"

        if [[ -f "$module_path" ]]; then
            log_debug "Loading module: $module"
            source "$module_path"
        else
            log_warn "Module not found: $module (using fallback)"
        fi
    done

    log_success "Modules loaded"
}

################################################################################
# Main Installation Flow
################################################################################

main() {
    print_banner

    log_info "LogOS Installation Started"
    log_info "Installation log: $INSTALL_LOG"

    # Initialize progress
    start_progress $TOTAL_STEPS

    # Step 0: Pre-flight checks
    next_step
    if command -v module_00_preflight &>/dev/null; then
        module_00_preflight
    else
        log_warn "Pre-flight module not found, using compatibility mode"
        # Fall back to inline checks
        source "${SCRIPT_DIR}/lib/validation.sh"
        validate_install_environment || exit 1
    fi
    complete_step

    # Gather user configuration
    log_step "1" "Configuration"
    gather_user_configuration
    confirm_installation
    next_step
    complete_step

    # Step 1: Disk setup
    next_step
    log_step "2" "Disk Preparation"
    source "${SCRIPT_DIR}/modules/partitioning.sh"
    prepare_disk
    create_partitions
    setup_encryption
    mount_filesystems
    complete_step

    # Step 2: Base system installation (Tier 0)
    next_step
    log_step "3" "Base System Installation (Tier 0)"
    source "${SCRIPT_DIR}/modules/tier0.sh"
    install_tier0
    complete_step

    # Step 3: Security infrastructure (Tier 1)
    next_step
    log_step "4" "Security Infrastructure (Tier 1)"
    source "${SCRIPT_DIR}/modules/tier1.sh"
    install_tier1
    complete_step

    # Step 4: System configuration
    next_step
    log_step "5" "System Configuration"
    generate_fstab
    source "${SCRIPT_DIR}/modules/chroot.sh"
    configure_system_chroot
    complete_step

    # Step 5: Desktop Environment Installation
    next_step
    log_step "6" "Desktop Environment Installation"
    source "${SCRIPT_DIR}/modules/60-desktop.sh"
    install_desktop
    complete_step

    # Step 6: Bootloader & Ringed City profiles
    next_step
    log_step "7" "Bootloader Installation"
    source "${SCRIPT_DIR}/modules/bootloader.sh"
    install_bootloader
    create_ringed_city_profiles
    complete_step

    # Step 7: Finalization
    next_step
    log_step "8" "Finalization"
    finalize_installation
    complete_step
    # Installation complete
    installation_complete
}

################################################################################
# User Configuration
################################################################################

gather_user_configuration() {
    log_info "Gathering installation configuration..."

    # Check if config already exists (resume)
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "Found existing configuration file"
        read -p "Resume with existing configuration? (y/N): " resume
        if [[ "$resume" =~ ^[Yy]$ ]]; then
            source "$CONFIG_FILE"
            SECURE_BOOT="${SECURE_BOOT:-n}"
            log_success "Configuration loaded"
            return
        fi
    fi

    # Disk selection
    echo ""
    echo "Available disks:"
    lsblk -d -o NAME,SIZE,TYPE,MODEL | grep disk
    echo ""
    while true; do
        read -p "Enter target disk (e.g., sda, nvme0n1): " disk_input
        DISK="/dev/${disk_input}"

        if validate_disk "$DISK"; then
            break
        fi
        log_error "Invalid disk selection. Please try again."
    done

    # Basic configuration
    read -p "Hostname [logos]: " HOSTNAME
    HOSTNAME="${HOSTNAME:-logos}"

    read -p "Username [logos]: " USERNAME
    USERNAME="${USERNAME:-logos}"

    read -p "Timezone (e.g., America/New_York) [America/New_York]: " TIMEZONE
    TIMEZONE="${TIMEZONE:-America/New_York}"

    # LUKS passphrase
    while true; do
        read -s -p "LUKS encryption passphrase (20+ chars): " LUKS_PASS
        echo ""
        if [[ ${#LUKS_PASS} -lt 20 ]]; then
            log_error "Passphrase too short (minimum 20 characters)"
            continue
        fi
        read -s -p "Confirm passphrase: " LUKS_PASS_CONFIRM
        echo ""
        if [[ "$LUKS_PASS" == "$LUKS_PASS_CONFIRM" ]]; then
            break
        fi
        log_error "Passphrases do not match"
    done

    # Root password
    while true; do
        read -s -p "Root password: " ROOT_PASS
        echo ""
        read -s -p "Confirm root password: " ROOT_PASS_CONFIRM
        echo ""
        [[ "$ROOT_PASS" == "$ROOT_PASS_CONFIRM" ]] && break
        log_error "Passwords do not match"
    done

    # User password
    while true; do
        read -s -p "User password: " USER_PASS
        echo ""
        read -s -p "Confirm user password: " USER_PASS_CONFIRM
        echo ""
        [[ "$USER_PASS" == "$USER_PASS_CONFIRM" ]] && break
        log_error "Passwords do not match"
    done

    # GPU type
    echo ""
    echo "GPU Type:"
    echo "1) AMD (Recommended)"
    echo "2) NVIDIA"
    echo "3) Intel"
    echo "4) None"
    read -p "Selection [1]: " gpu_choice
    case "${gpu_choice:-1}" in
        1) GPU_TYPE="amd" ;;
        2) GPU_TYPE="nvidia" ;;
        3) GPU_TYPE="intel" ;;
        *) GPU_TYPE="none" ;;
    esac

    # Desktop environment
    echo ""
    echo "Desktop Environment:"
    echo "1) GNOME"
    echo "2) KDE Plasma"
    echo "3) XFCE"
    echo "4) i3-wm"
    echo "5) None (server)"
    read -p "Selection [1]: " de_choice
    case "${de_choice:-1}" in
        1) DESKTOP_ENV="gnome" ;;
        2) DESKTOP_ENV="kde" ;;
        3) DESKTOP_ENV="xfce" ;;
        4) DESKTOP_ENV="i3" ;;
        *) DESKTOP_ENV="none" ;;
    esac

    # Secure Boot
    echo ""
    read -p "Configure Secure Boot with sbctl? (y/N): " SECURE_BOOT
    SECURE_BOOT="${SECURE_BOOT:-n}"

    # Save configuration
    save_configuration

    log_success "Configuration gathered"
}

save_configuration() {
    cat > "$CONFIG_FILE" <<EOF
# LogOS Installation Configuration
DISK="$DISK"
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
TIMEZONE="$TIMEZONE"
GPU_TYPE="$GPU_TYPE"
DESKTOP_ENV="$DESKTOP_ENV"
SECURE_BOOT="$SECURE_BOOT"
LOCALE="${LOCALE:-en_US.UTF-8}"
KEYMAP="${KEYMAP:-us}"
EOF
    chmod 600 "$CONFIG_FILE"
}

confirm_installation() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║            Installation Configuration Summary               ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Target Disk:    $DISK"
    echo "  Hostname:       $HOSTNAME"
    echo "  Username:       $USERNAME"
    echo "  Timezone:       $TIMEZONE"
    echo "  GPU:            $GPU_TYPE"
    echo "  Desktop:        $DESKTOP_ENV"
    echo ""
    echo -e "${RED}⚠ ALL DATA ON $DISK WILL BE PERMANENTLY ERASED! ⚠${NC}"
    echo ""
    read -p "Type 'YES' in capital letters to proceed: " confirm

    if [[ "$confirm" != "YES" ]]; then
        log_warn "Installation cancelled by user"
        exit 0
    fi
}

finalize_installation() {
    log_info "Finalizing installation..."

    # Unmount filesystems
    log_info "Unmounting filesystems..."
    sync
    umount -R /mnt || log_warn "Some filesystems failed to unmount"

    # Close encrypted partition
    log_info "Closing encrypted partition..."
    cryptsetup close cryptroot || log_warn "Failed to close cryptroot"

    log_success "Installation finalized"
}

installation_complete() {
    local duration=$(($(date +%s) - START_TIME))

    clear
    cat << 'EOF'

╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║                     LogOS Installation Complete!                           ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝

Next Steps:

1. IMPORTANT: Remove the installation media (USB/ISO) from your system
2. Reboot the system:

   # reboot

3. Your system should automatically boot into LogOS (GRUB bootloader)
4. At the GRUB menu, select your Ringed City profile:
   - Midir (Balanced) - Recommended for daily use
   - Gael (Maximum Security) - For sensitive operations
   - Halflight (Performance) - For gaming/media production

5. Login with your username and password

6. After first boot, install desktop environment (if selected):

   $ cd LogOS/installer/modules
   $ ./tier2-standalone.sh

7. Optionally install specialized tools:

   $ ./tier3-standalone.sh

If the system boots back to the installation media instead of LogOS:
- Check your BIOS/UEFI boot order settings
- Ensure "LogOS" is set as the first boot option
- Disable boot from USB/CD in BIOS if needed

Documentation:
- Full guide: /usr/share/doc/logos/LogOS_Build_Guide_2025_MASTER_v7.md
- Quick reference: /usr/share/doc/logos/QUICKSTART.md

Support:
- GitHub: https://github.com/crussella0129/LogOS
- Issues: https://github.com/crussella0129/LogOS/issues

EOF

    log_summary "SUCCESS" "$duration"

    echo -e "${GREEN}Installation completed successfully in ${duration}s${NC}"
    echo ""
}

################################################################################
# Entry Point
################################################################################

# Load modules
load_modules

# Run main installation
main "$@"

# Exit successfully
exit 0





