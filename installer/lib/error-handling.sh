#!/bin/bash

################################################################################
# LogOS Installer - Error Handling Library
################################################################################

# Error handling state
declare -g ERROR_OCCURRED=0
declare -g CLEANUP_REGISTERED=0
declare -a CLEANUP_FUNCTIONS=()

################################################################################
# Error Handler
################################################################################

handle_error() {
    local exit_code=$?
    local line_no=$1
    local bash_lineno=$2
    local last_command=$3

    ERROR_OCCURRED=1

    log_fatal "Installation failed at line $line_no"
    log_error "Exit code: $exit_code"
    log_error "Command: $last_command"
    log_error "Bash line: $bash_lineno"

    # Log stack trace
    log_error "Stack trace:"
    local frame=0
    while caller $frame >> "$INSTALL_LOG_VERBOSE" 2>&1; do
        ((frame++))
    done

    # Run cleanup
    cleanup_on_error

    # Show user-friendly error message
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                        Installation Failed                                   ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "An error occurred during installation."
    echo "Please check the log file for details: $INSTALL_LOG"
    echo ""
    echo "You can report this issue at: https://github.com/crussella0129/LogOS/issues"
    echo ""

    exit $exit_code
}

################################################################################
# Cleanup Registration
################################################################################

register_cleanup() {
    local cleanup_func=$1
    CLEANUP_FUNCTIONS+=("$cleanup_func")

    if [[ $CLEANUP_REGISTERED -eq 0 ]]; then
        trap 'handle_error ${LINENO} ${BASH_LINENO} "$BASH_COMMAND"' ERR
        trap 'cleanup_on_exit' EXIT
        CLEANUP_REGISTERED=1
    fi
}

################################################################################
# Cleanup Functions
################################################################################

cleanup_on_error() {
    log_warn "Performing emergency cleanup..."

    # Run registered cleanup functions in reverse order
    for ((i=${#CLEANUP_FUNCTIONS[@]}-1; i>=0; i--)); do
        local func="${CLEANUP_FUNCTIONS[$i]}"
        log_debug "Running cleanup: $func"
        $func || log_warn "Cleanup function failed: $func"
    done

    # Default cleanup actions
    default_cleanup

    log_warn "Emergency cleanup completed"
}

cleanup_on_exit() {
    if [[ $ERROR_OCCURRED -eq 0 ]]; then
        log_debug "Normal exit, running cleanup..."
    fi

    # Clean temporary files
    rm -f /tmp/logos-*.tmp 2>/dev/null || true
}

default_cleanup() {
    log_debug "Running default cleanup actions..."

    # Unmount filesystems
    if mountpoint -q /mnt 2>/dev/null; then
        log_warn "Unmounting /mnt filesystems..."
        umount -R /mnt 2>/dev/null || true
        sleep 1
    fi

    # Close cryptsetup
    if [[ -b /dev/mapper/cryptroot ]]; then
        log_warn "Closing encrypted partition..."
        cryptsetup close cryptroot 2>/dev/null || true
    fi

    # Deactivate any LVM volumes
    if command -v vgchange &>/dev/null; then
        vgchange -an 2>/dev/null || true
    fi

    log_debug "Default cleanup completed"
}

################################################################################
# Safe Command Execution
################################################################################

safe_run() {
    local cmd="$*"

    log_debug "Safe run: $cmd"

    if ! eval "$cmd"; then
        local exit_code=$?
        log_error "Safe run failed: $cmd (exit $exit_code)"
        return $exit_code
    fi

    return 0
}

safe_run_critical() {
    local cmd="$*"

    log_info "Critical command: $cmd"

    if ! eval "$cmd"; then
        local exit_code=$?
        log_fatal "Critical command failed: $cmd (exit $exit_code)"
        handle_error ${LINENO} ${BASH_LINENO} "$cmd"
    fi

    return 0
}

################################################################################
# Retry Logic
################################################################################

retry_command() {
    local max_attempts=$1
    shift
    local cmd="$*"
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Attempt $attempt/$max_attempts: $cmd"

        if eval "$cmd"; then
            log_success "Command succeeded on attempt $attempt"
            return 0
        fi

        local exit_code=$?

        if [[ $attempt -lt $max_attempts ]]; then
            log_warn "Attempt $attempt failed (exit $exit_code), retrying..."
            sleep $((attempt * 2))
        else
            log_error "Command failed after $max_attempts attempts: $cmd"
            return $exit_code
        fi

        ((attempt++))
    done
}

################################################################################
# Validation Helpers
################################################################################

require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_fatal "This script must be run as root"
        exit 1
    fi
}

require_command() {
    local cmd=$1

    if ! command -v "$cmd" &>/dev/null; then
        log_fatal "Required command not found: $cmd"
        exit 1
    fi
}

require_file() {
    local file=$1

    if [[ ! -f "$file" ]]; then
        log_fatal "Required file not found: $file"
        exit 1
    fi
}

require_dir() {
    local dir=$1

    if [[ ! -d "$dir" ]]; then
        log_fatal "Required directory not found: $dir"
        exit 1
    fi
}

################################################################################
# Assertion Functions
################################################################################

assert_equal() {
    local actual=$1
    local expected=$2
    local message=${3:-"Assertion failed"}

    if [[ "$actual" != "$expected" ]]; then
        log_fatal "$message: expected '$expected', got '$actual'"
        exit 1
    fi
}

assert_not_empty() {
    local value=$1
    local message=${2:-"Value is empty"}

    if [[ -z "$value" ]]; then
        log_fatal "$message"
        exit 1
    fi
}

assert_file_exists() {
    local file=$1
    local message=${2:-"File does not exist: $file"}

    if [[ ! -f "$file" ]]; then
        log_fatal "$message"
        exit 1
    fi
}

assert_block_device() {
    local device=$1
    local message=${2:-"Not a block device: $device"}

    if [[ ! -b "$device" ]]; then
        log_fatal "$message"
        exit 1
    fi
}

################################################################################
# User Confirmation
################################################################################

confirm_or_exit() {
    local prompt=$1
    local response

    read -p "$prompt (yes/no): " response

    if [[ "$response" != "yes" ]]; then
        log_warn "User declined confirmation"
        exit 0
    fi
}

confirm_destructive() {
    local action=$1

    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                            DESTRUCTIVE ACTION                                ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}WARNING: $action${NC}"
    echo ""

    confirm_or_exit "Type 'yes' to confirm this destructive action"
}
