#!/bin/bash

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="$(cd "${SELF_DIR}/../installer" && pwd)"

if [[ ! -d "$INSTALLER_DIR" ]]; then
    echo "Installer modules not found at: $INSTALLER_DIR" >&2
    exit 1
fi

# Use legacy installer directory for shared libs and templates.
export SCRIPT_DIR="$INSTALLER_DIR"

source "${INSTALLER_DIR}/lib/common.sh"
source "${INSTALLER_DIR}/lib/logging.sh"
source "${INSTALLER_DIR}/lib/error-handling.sh"
source "${INSTALLER_DIR}/lib/validation.sh"

CONFIG_FILE="${CONFIG_FILE:-/tmp/logos-install.conf}"
TOTAL_STEPS=9

init_logging
register_cleanup default_cleanup

require_tty() {
    if [[ ! -t 0 ]]; then
        log_fatal "This installer requires an interactive TTY."
        exit 1
    fi
}

prompt_enter() {
    local _reply
    if ! read -r -p "Press ENTER to continue, or Ctrl+C to abort... " _reply; then
        log_fatal "Input stream closed. Run from an interactive terminal."
        exit 1
    fi
}

prompt_value() {
    local prompt=$1
    local var=$2
    local default=${3:-}
    local value

    if ! read -r -p "$prompt" value; then
        log_fatal "Input stream closed. Run from an interactive terminal."
        exit 1
    fi

    if [[ -z "$value" ]]; then
        value="$default"
    fi

    printf -v "$var" "%s" "$value"
}

prompt_secret() {
    local prompt=$1
    local var=$2
    local value

    if ! read -r -s -p "$prompt" value; then
        echo ""
        log_fatal "Input stream closed. Run from an interactive terminal."
        exit 1
    fi

    echo ""
    printf -v "$var" "%s" "$value"
}

print_banner() {
    clear
    cat << 'EOF'
============================================================
                 LogOS Installer-Proto
          Hardened Arch-based LogOS installer
============================================================
EOF
    echo ""
    echo "WARNING: This will ERASE ALL DATA on the selected disk!"
    echo ""
}

source_module() {
    local module_name=$1
    local module_path="${INSTALLER_DIR}/modules/${module_name}"

    if [[ ! -f "$module_path" ]]; then
        log_fatal "Missing module: ${module_name}"
        exit 1
    fi

    source "$module_path"
}

load_preflight() {
    source_module "00-preflight.sh"
}

load_partitioning() {
    source_module "partitioning.sh"
}

load_tier0() {
    source_module "tier0.sh"
}

load_tier1() {
    source_module "tier1.sh"
}

load_chroot() {
    source_module "chroot.sh"
}

load_bootloader() {
    source_module "bootloader.sh"
}

load_desktop() {
    source_module "60-desktop.sh"
}

save_configuration() {
    cat > "$CONFIG_FILE" <<EOF
# LogOS Installer-Proto config
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
    chmod 600 "$CONFIG_FILE"
}

load_configuration() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_fatal "Config not found: $CONFIG_FILE"
        exit 1
    fi
    source "$CONFIG_FILE"
}

gather_user_configuration() {
    log_info "Gathering installation configuration..."

    echo ""
    echo "Available disks:"
    lsblk -d -o NAME,SIZE,TYPE,MODEL | grep disk || true
    echo ""

    while true; do
        prompt_value "Enter target disk (e.g., sda, nvme0n1): " disk_input ""
        DISK="/dev/${disk_input}"
        if validate_disk "$DISK"; then
            break
        fi
        log_error "Invalid disk selection. Please try again."
    done

    while true; do
        prompt_value "Hostname [logos]: " HOSTNAME "logos"
        if validate_hostname "$HOSTNAME"; then
            break
        fi
        log_error "Invalid hostname. Please try again."
    done

    while true; do
        prompt_value "Username [logos]: " USERNAME "logos"
        if validate_username "$USERNAME"; then
            break
        fi
        log_error "Invalid username. Please try again."
    done

    while true; do
        prompt_value "Timezone (e.g., America/New_York) [America/New_York]: " TIMEZONE "America/New_York"
        if validate_timezone "$TIMEZONE"; then
            break
        fi
        log_error "Invalid timezone. Please try again."
    done

    prompt_value "Locale [en_US.UTF-8]: " LOCALE "en_US.UTF-8"
    prompt_value "Keyboard layout [us]: " KEYMAP "us"

    while true; do
        prompt_secret "LUKS encryption passphrase (20+ chars): " LUKS_PASS
        if ! validate_luks_passphrase "$LUKS_PASS"; then
            continue
        fi
        prompt_secret "Confirm passphrase: " LUKS_PASS_CONFIRM
        if [[ "$LUKS_PASS" == "$LUKS_PASS_CONFIRM" ]]; then
            break
        fi
        log_error "Passphrases do not match."
    done

    while true; do
        prompt_secret "Root password: " ROOT_PASS
        prompt_secret "Confirm root password: " ROOT_PASS_CONFIRM
        [[ "$ROOT_PASS" == "$ROOT_PASS_CONFIRM" ]] && break
        log_error "Passwords do not match."
    done

    while true; do
        prompt_secret "User password: " USER_PASS
        prompt_secret "Confirm user password: " USER_PASS_CONFIRM
        [[ "$USER_PASS" == "$USER_PASS_CONFIRM" ]] && break
        log_error "Passwords do not match."
    done

    echo ""
    echo "GPU Type:"
    echo "1) AMD (Recommended)"
    echo "2) NVIDIA"
    echo "3) Intel"
    echo "4) None"
    prompt_value "Selection [1]: " gpu_choice "1"
    case "$gpu_choice" in
        1) GPU_TYPE="amd" ;;
        2) GPU_TYPE="nvidia" ;;
        3) GPU_TYPE="intel" ;;
        *) GPU_TYPE="none" ;;
    esac

    echo ""
    echo "Desktop Environment:"
    echo "1) GNOME"
    echo "2) KDE Plasma"
    echo "3) XFCE"
    echo "4) i3-wm"
    echo "5) None (server)"
    prompt_value "Selection [1]: " de_choice "1"
    case "$de_choice" in
        1) DESKTOP_ENV="gnome" ;;
        2) DESKTOP_ENV="kde" ;;
        3) DESKTOP_ENV="xfce" ;;
        4) DESKTOP_ENV="i3" ;;
        *) DESKTOP_ENV="none" ;;
    esac

    echo ""
    prompt_value "Configure Secure Boot with sbctl? (y/N): " SECURE_BOOT "n"

    save_configuration
    log_success "Configuration saved to $CONFIG_FILE"
}

confirm_installation() {
    echo ""
    echo "============================================================"
    echo "Installation Configuration Summary"
    echo "============================================================"
    echo "Target Disk:    $DISK"
    echo "Hostname:       $HOSTNAME"
    echo "Username:       $USERNAME"
    echo "Timezone:       $TIMEZONE"
    echo "Locale:         $LOCALE"
    echo "Keyboard:       $KEYMAP"
    echo "GPU:            $GPU_TYPE"
    echo "Desktop:        $DESKTOP_ENV"
    echo "Secure Boot:    $SECURE_BOOT"
    echo "============================================================"
    echo ""
    echo "WARNING: ALL DATA ON $DISK WILL BE PERMANENTLY ERASED!"
    echo ""
    prompt_value "Type 'YES' in capital letters to proceed: " confirm ""

    if [[ "$confirm" != "YES" ]]; then
        log_warn "Installation cancelled by user."
        exit 0
    fi
}

finalize_installation() {
    log_info "Finalizing installation..."
    sync
    umount -R /mnt || log_warn "Some filesystems failed to unmount"
    cryptsetup close cryptroot || log_warn "Failed to close cryptroot"
    log_success "Installation finalized"
}

run_preflight() {
    load_preflight
    if command -v module_00_preflight &>/dev/null; then
        module_00_preflight
    else
        log_warn "Pre-flight module not found, using compatibility mode"
        validate_install_environment || exit 1
    fi
}

run_install() {
    start_progress "$TOTAL_STEPS"

    next_step
    run_preflight
    complete_step

    log_step "1" "Configuration"
    gather_user_configuration
    confirm_installation
    next_step
    complete_step

    next_step
    log_step "2" "Disk Preparation"
    load_partitioning
    prepare_disk
    create_partitions
    setup_encryption
    mount_filesystems
    complete_step

    next_step
    log_step "3" "Base System Installation (Tier 0)"
    load_tier0
    install_tier0
    complete_step

    next_step
    log_step "4" "Security Infrastructure (Tier 1)"
    load_tier1
    install_tier1
    complete_step

    next_step
    log_step "5" "System Configuration"
    generate_fstab
    load_chroot
    configure_system_chroot
    complete_step

    next_step
    log_step "6" "Desktop Environment Installation"
    load_desktop
    install_desktop
    complete_step

    next_step
    log_step "7" "Bootloader Installation"
    load_bootloader
    install_bootloader
    create_ringed_city_profiles
    complete_step

    next_step
    log_step "8" "Finalization"
    finalize_installation
    complete_step
}

run_resume() {
    load_configuration
    confirm_installation
    run_install
}

show_logs() {
    echo "Install log: ${INSTALL_LOG}"
    echo "Verbose log: ${INSTALL_LOG_VERBOSE}"
}

usage() {
    cat << 'EOF'
LogOS Installer-Proto

Usage:
  ./logos-installer.sh [command]

Commands:
  run       Start a full install (default)
  resume    Resume from an existing config file
  config    Collect and save configuration only
  validate  Run pre-flight checks only
  logs      Show log file locations
  help      Show this help text
EOF
}

main() {
    require_tty
    print_banner
    prompt_enter

    local command=${1:-run}
    case "$command" in
        run)
            run_install
            ;;
        resume)
            run_resume
            ;;
        config)
            gather_user_configuration
            ;;
        validate)
            run_preflight
            ;;
        logs)
            show_logs
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            echo "Unknown command: $command" >&2
            usage
            exit 1
            ;;
    esac
}

main "$@"
