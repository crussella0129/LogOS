#!/bin/bash

################################################################################
# LogOS Installer - Logging Library
################################################################################

# Log levels
export LOG_LEVEL_DEBUG=0
export LOG_LEVEL_INFO=1
export LOG_LEVEL_WARN=2
export LOG_LEVEL_ERROR=3
export LOG_LEVEL_FATAL=4

# Current log level (can be set via LOGOS_LOG_LEVEL env var)
export CURRENT_LOG_LEVEL=${LOGOS_LOG_LEVEL:-$LOG_LEVEL_INFO}

# Log file location
export INSTALL_LOG="${INSTALL_LOG:-/tmp/logos-install.log}"
export INSTALL_LOG_VERBOSE="${INSTALL_LOG_VERBOSE:-/tmp/logos-install-verbose.log}"

################################################################################
# Initialize Logging
################################################################################

init_logging() {
    # Create log files (with fallback if /tmp isn't writable)
    if ! touch "$INSTALL_LOG" "$INSTALL_LOG_VERBOSE" 2>/dev/null; then
        local fallback_dir="/root/logos-installer-logs"
        mkdir -p "$fallback_dir" 2>/dev/null || true
        INSTALL_LOG="${fallback_dir}/logos-install.log"
        INSTALL_LOG_VERBOSE="${fallback_dir}/logos-install-verbose.log"
        if ! touch "$INSTALL_LOG" "$INSTALL_LOG_VERBOSE" 2>/dev/null; then
            INSTALL_LOG="/dev/null"
            INSTALL_LOG_VERBOSE="/dev/null"
        fi
    fi

    # Log header
    {
        echo "╔══════════════════════════════════════════════════════════════════════════════╗"
        echo "║                     LogOS Installation Log                                  ║"
        echo "║                     Started: $(date '+%Y-%m-%d %H:%M:%S')                              ║"
        echo "╚══════════════════════════════════════════════════════════════════════════════╝"
        echo ""
    } | tee -a "$INSTALL_LOG" "$INSTALL_LOG_VERBOSE" >/dev/null || true
}

################################################################################
# Logging Functions
################################################################################

log_debug() {
    if [[ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_DEBUG ]]; then
        echo "[$(date '+%H:%M:%S')] [DEBUG] $*" | tee -a "$INSTALL_LOG_VERBOSE" >&2 || true
    else
        echo "[$(date '+%H:%M:%S')] [DEBUG] $*" >> "$INSTALL_LOG_VERBOSE"
    fi
}

log_info() {
    if [[ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_INFO ]]; then
        echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $*" | tee -a "$INSTALL_LOG" "$INSTALL_LOG_VERBOSE" || true
    else
        echo "[$(date '+%H:%M:%S')] [INFO] $*" >> "$INSTALL_LOG" "$INSTALL_LOG_VERBOSE"
    fi
}

log_warn() {
    if [[ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_WARN ]]; then
        echo -e "${YELLOW}[$(date '+%H:%M:%S')] [WARN]${NC} $*" | tee -a "$INSTALL_LOG" "$INSTALL_LOG_VERBOSE" >&2 || true
    else
        echo "[$(date '+%H:%M:%S')] [WARN] $*" >> "$INSTALL_LOG" "$INSTALL_LOG_VERBOSE"
    fi
}

log_error() {
    if [[ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_ERROR ]]; then
        echo -e "${RED}[$(date '+%H:%M:%S')] [ERROR]${NC} $*" | tee -a "$INSTALL_LOG" "$INSTALL_LOG_VERBOSE" >&2 || true
    else
        echo "[$(date '+%H:%M:%S')] [ERROR] $*" >> "$INSTALL_LOG" "$INSTALL_LOG_VERBOSE"
    fi
}

log_fatal() {
    echo -e "${RED}[$(date '+%H:%M:%S')] [FATAL]${NC} $*" | tee -a "$INSTALL_LOG" "$INSTALL_LOG_VERBOSE" >&2 || true
}

log_success() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] [✓]${NC} $*" | tee -a "$INSTALL_LOG" "$INSTALL_LOG_VERBOSE" || true
}

log_step() {
    local step_num=$1
    local step_desc=$2

    echo "" | tee -a "$INSTALL_LOG" "$INSTALL_LOG_VERBOSE" || true
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}" | tee -a "$INSTALL_LOG" "$INSTALL_LOG_VERBOSE" || true
    echo -e "${GREEN}Step $step_num: $step_desc${NC}" | tee -a "$INSTALL_LOG" "$INSTALL_LOG_VERBOSE" || true
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}" | tee -a "$INSTALL_LOG" "$INSTALL_LOG_VERBOSE" || true
    echo "" | tee -a "$INSTALL_LOG" "$INSTALL_LOG_VERBOSE" || true
}

################################################################################
# Command Logging
################################################################################

log_cmd() {
    local cmd="$*"
    log_debug "Executing: $cmd"

    if eval "$cmd" >> "$INSTALL_LOG_VERBOSE" 2>&1; then
        log_debug "Command succeeded: $cmd"
        return 0
    else
        local exit_code=$?
        log_error "Command failed (exit $exit_code): $cmd"
        return $exit_code
    fi
}

log_cmd_output() {
    local cmd="$*"
    log_debug "Executing with output: $cmd"

    local output
    if output=$(eval "$cmd" 2>&1); then
        log_debug "Command output: $output"
        echo "$output"
        return 0
    else
        local exit_code=$?
        log_error "Command failed (exit $exit_code): $cmd"
        log_error "Output: $output"
        return $exit_code
    fi
}

################################################################################
# Progress Tracking
################################################################################

declare -g TOTAL_STEPS=0
declare -g CURRENT_STEP=0
declare -g STEP_START_TIME=0

start_progress() {
    TOTAL_STEPS=$1
    CURRENT_STEP=0
    log_info "Installation process: 0/$TOTAL_STEPS steps"
}

next_step() {
    ((CURRENT_STEP++))
    STEP_START_TIME=$(date +%s)
    local percent=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    log_info "Progress: $CURRENT_STEP/$TOTAL_STEPS ($percent%)"
}

complete_step() {
    local duration=$(($(date +%s) - STEP_START_TIME))
    log_success "Step completed in ${duration}s"
}

################################################################################
# Installation Summary
################################################################################

log_summary() {
    local status=$1
    local duration=$2

    {
        echo ""
        echo "╔══════════════════════════════════════════════════════════════════════════════╗"
        echo "║                     Installation Summary                                    ║"
        echo "╚══════════════════════════════════════════════════════════════════════════════╝"
        echo ""
        echo "Status:     $status"
        echo "Duration:   ${duration}s"
        echo "Log File:   $INSTALL_LOG"
        echo "Verbose Log: $INSTALL_LOG_VERBOSE"
        echo ""
        echo "Completed:  $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
    } | tee -a "$INSTALL_LOG" "$INSTALL_LOG_VERBOSE" || true
}

################################################################################
# Diagnostic Information
################################################################################

log_system_info() {
    log_info "Collecting system information..."

    {
        echo "=== System Information ==="
        echo "Hostname: $(hostname)"
        echo "Kernel: $(uname -r)"
        echo "Architecture: $(uname -m)"
        echo ""
        echo "=== CPU Information ==="
        lscpu | grep -E "Model name|CPU\(s\):|Thread|Core" || echo "lscpu failed"
        echo ""
        echo "=== Memory Information ==="
        free -h || echo "free failed"
        echo ""
        echo "=== Disk Information ==="
        lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT || echo "lsblk failed"
        echo ""
        echo "=== Network Interfaces ==="
        ip link show || echo "ip link failed"
        echo ""
    } >> "$INSTALL_LOG_VERBOSE"

    log_success "System information logged"
}


