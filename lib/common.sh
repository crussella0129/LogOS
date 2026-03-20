#!/usr/bin/env bash
# lib/common.sh — LogOS Artix shared library
# Sourced by every companion script. Provides logging, config loading,
# package helpers, environment checks, and error handling.
# Artix Linux (OpenRC) — no systemd dependency.

set -euo pipefail

# ── Path bootstrapping ──────────────────────────────────────────────
# Resolve the canonical location of the lib/ and scripts/ directories
# regardless of where a script is invoked from.
LOGOS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGOS_SCRIPT_DIR="$(cd "${LOGOS_LIB_DIR}/../scripts" 2>/dev/null && pwd || echo "${LOGOS_LIB_DIR}/../scripts")"
LOGOS_ROOT="$(cd "${LOGOS_LIB_DIR}/.." && pwd)"

# ── Logging ─────────────────────────────────────────────────────────
# Timestamped, colored output. LOGOS_SECTION is set by each script.
LOGOS_SECTION="${LOGOS_SECTION:-logos}"

_ts() { date '+%H:%M:%S'; }

log()      { printf '\033[0;37m[%s] [%s] %s\033[0m\n' "$(_ts)" "${LOGOS_SECTION}" "$*"; }
log_ok()   { printf '\033[0;32m[%s] [%s] ✓ %s\033[0m\n' "$(_ts)" "${LOGOS_SECTION}" "$*"; }
log_warn() { printf '\033[0;33m[%s] [%s] ⚠ %s\033[0m\n' "$(_ts)" "${LOGOS_SECTION}" "$*" >&2; }
log_err()  { printf '\033[0;31m[%s] [%s] ✗ %s\033[0m\n' "$(_ts)" "${LOGOS_SECTION}" "$*" >&2; }

# ── Error trap ──────────────────────────────────────────────────────
trap_err() {
  local exit_code=$?
  local line="${1:-unknown}"
  local cmd="${2:-unknown}"
  log_err "FAILED at ${BASH_SOURCE[1]:-script}:${line} — command: ${cmd} (exit ${exit_code})"
  exit "${exit_code}"
}
trap 'trap_err ${LINENO} "${BASH_COMMAND}"' ERR

# ── Configuration ───────────────────────────────────────────────────
load_config() {
  local config_path="${1:-${LOGOS_ROOT}/logos.conf}"

  if [[ ! -f "${config_path}" ]]; then
    log_err "Config not found: ${config_path}"
    log_err "Copy logos.conf.example to logos.conf and edit it."
    return 1
  fi

  # shellcheck source=/dev/null
  source "${config_path}"

  # Validate mandatory fields
  local missing=()
  [[ -z "${LOGOS_DISK:-}" ]]     && missing+=("LOGOS_DISK")
  [[ -z "${LOGOS_HOSTNAME:-}" ]] && missing+=("LOGOS_HOSTNAME")
  [[ -z "${LOGOS_USERNAME:-}" ]] && missing+=("LOGOS_USERNAME")
  [[ -z "${LOGOS_TIMEZONE:-}" ]] && missing+=("LOGOS_TIMEZONE")

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_err "Missing mandatory config: ${missing[*]}"
    return 1
  fi

  log_ok "Configuration loaded from ${config_path}"
}

# ── Package helpers ─────────────────────────────────────────────────
install_pkgs() {
  if [[ $# -eq 0 ]]; then
    log_warn "install_pkgs called with no arguments"
    return 0
  fi
  log "Installing: $*"
  pacman -S --noconfirm --needed "$@"
}

# ── Environment checks ─────────────────────────────────────────────
require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    log_err "This script must be run as root."
    exit 1
  fi
}

require_chroot() {
  # In a chroot, / has a different device number than /proc/1/root
  if [[ "$(stat -c %d:%i /)" == "$(stat -c %d:%i /proc/1/root 2>/dev/null)" ]]; then
    log_err "This script must be run inside artix-chroot."
    exit 1
  fi
}

require_live_env() {
  if [[ ! -d /run/artix ]] && [[ ! -f /etc/artix-release ]]; then
    log_warn "This does not appear to be an Artix live environment."
    log_warn "Proceeding anyway — some checks may fail."
  fi
}

# ── Interactive confirmation ────────────────────────────────────────
confirm() {
  local prompt="${1:-Continue?}"

  if [[ "${LOGOS_NONINTERACTIVE:-0}" == "1" ]]; then
    log "Non-interactive mode: auto-confirming '${prompt}'"
    return 0
  fi

  printf '\033[1;33m%s [y/N]: \033[0m' "${prompt}"
  local reply
  read -r reply
  case "${reply}" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) log_err "Aborted by user."; return 1 ;;
  esac
}

# ── Partition variable derivation ───────────────────────────────────
# Derives EFI_PART, BOOT_PART, ROOT_PART from LOGOS_DISK.
# Handles NVMe naming (e.g., /dev/nvme0n1 → /dev/nvme0n1p1).
set_partition_vars() {
  local disk="${LOGOS_DISK:?LOGOS_DISK not set}"
  local suffix=""

  # NVMe and loop devices use a 'p' separator before partition number
  if [[ "${disk}" =~ nvme[0-9]+n[0-9]+$ ]] || [[ "${disk}" =~ loop[0-9]+$ ]]; then
    suffix="p"
  fi

  EFI_PART="${disk}${suffix}1"
  BOOT_PART="${disk}${suffix}2"
  ROOT_PART="${disk}${suffix}3"

  export EFI_PART BOOT_PART ROOT_PART
}
