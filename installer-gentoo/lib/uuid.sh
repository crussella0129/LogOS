#!/usr/bin/env bash
# LogOS Gentoo — UUID detection
# Detect LUKS and Btrfs UUIDs for GRUB and initramfs config

[[ -n "${_LOGOS_UUID_LOADED:-}" ]] && return 0
readonly _LOGOS_UUID_LOADED=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# Detect or accept LUKS UUID
# Sets: CRYPT_UUID
detect_crypt_uuid() {
  if [[ -n "${CRYPT_UUID_OVERRIDE:-}" ]]; then
    CRYPT_UUID="${CRYPT_UUID_OVERRIDE}"
    log "Using CRYPT_UUID override: ${CRYPT_UUID}"
    return 0
  fi

  local crypt_dev crypt_count
  crypt_count="$(blkid -t TYPE=crypto_LUKS -o device | wc -l)"
  if [[ "${crypt_count}" -eq 0 ]]; then
    die "Unable to locate crypto_LUKS device. Set CRYPT_UUID_OVERRIDE."
  fi
  if [[ "${crypt_count}" -gt 1 ]]; then
    warn "Multiple LUKS devices found (${crypt_count}). Using first one."
    warn "Set CRYPT_UUID_OVERRIDE to specify explicitly."
    blkid -t TYPE=crypto_LUKS -o device | while read -r dev; do
      warn "  ${dev}: UUID=$(blkid -s UUID -o value "${dev}")"
    done
  fi
  crypt_dev="$(blkid -t TYPE=crypto_LUKS -o device | head -n1)"
  CRYPT_UUID="$(blkid -s UUID -o value "${crypt_dev}")"
  log "Detected CRYPT_UUID: ${CRYPT_UUID}"
}

# Detect or accept Btrfs UUID
# Sets: BTRFS_UUID
detect_btrfs_uuid() {
  if [[ -n "${BTRFS_UUID_OVERRIDE:-}" ]]; then
    BTRFS_UUID="${BTRFS_UUID_OVERRIDE}"
    log "Using BTRFS_UUID override: ${BTRFS_UUID}"
    return 0
  fi

  local root_dev btrfs_dev
  root_dev="$(findmnt -n -o SOURCE / || true)"
  if [[ -n "${root_dev}" ]]; then
    BTRFS_UUID="$(blkid -s UUID -o value "${root_dev}" || true)"
  else
    BTRFS_UUID=""
  fi

  if [[ -z "${BTRFS_UUID}" ]]; then
    btrfs_dev="$(blkid -t TYPE=btrfs -o device | head -n1 || true)"
    if [[ -z "${btrfs_dev}" ]]; then
      die "Unable to locate btrfs UUID. Set BTRFS_UUID_OVERRIDE."
    fi
    BTRFS_UUID="$(blkid -s UUID -o value "${btrfs_dev}")"
  fi
  log "Detected BTRFS_UUID: ${BTRFS_UUID}"
}

# Save UUIDs to file for later phases
save_uuids() {
  local uuid_file="${1:-/tmp/logos-uuids}"
  local tmp_file="${uuid_file}.tmp.$$"
  log "Saving UUIDs to ${uuid_file}"
  cat > "${tmp_file}" << EOF
CRYPT_UUID="${CRYPT_UUID}"
BTRFS_UUID="${BTRFS_UUID}"
EOF
  mv "${tmp_file}" "${uuid_file}" || die "Failed to save UUIDs atomically"
  chmod 600 "${uuid_file}"
}

# Load UUIDs from file
load_uuids() {
  local uuid_file="${1:-/tmp/logos-uuids}"
  if [[ ! -f "${uuid_file}" ]]; then
    die "UUID file not found: ${uuid_file}"
  fi
  # shellcheck source=/dev/null
  source "${uuid_file}"
  log "Loaded CRYPT_UUID=${CRYPT_UUID} BTRFS_UUID=${BTRFS_UUID}"
}
