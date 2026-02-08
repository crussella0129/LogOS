#!/usr/bin/env bash
# clean.sh — Wipe all build artifacts for a fresh installer run
#
# Closes stale LUKS mappings, unmounts filesystems, detaches loop devices,
# and removes build output (raw image, qcow2, mount tree, logs).
# Stage3 cache is preserved by default (use --all to remove it too).
#
# Usage: sudo ./installer/clean.sh [--all]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}/build"
IMG_RAW="${WORK_DIR}/logos-vm.raw"
MNT="${WORK_DIR}/mnt"
LOG_DIR="${SCRIPT_DIR}/logs"
LUKS_NAME="cryptroot"

log() { echo "[clean $(date +%H:%M:%S)] $*"; }

[[ "$(id -u)" -eq 0 ]] || { echo "Must run as root"; exit 1; }

WIPE_CACHE=false
if [[ "${1:-}" == "--all" ]]; then
    WIPE_CACHE=true
fi

# ---- Unmount everything under MNT ----
if mount | grep -q "${MNT}"; then
    log "Unmounting filesystems under ${MNT}"
    for mp in $(mount | grep "${MNT}" | awk '{print $3}' | sort -r); do
        log "  umount ${mp}"
        umount -l "${mp}" 2>/dev/null || true
    done
fi

# ---- Close LUKS ----
if [[ -e "/dev/mapper/${LUKS_NAME}" ]]; then
    log "Closing LUKS mapping '${LUKS_NAME}'"
    cryptsetup close "${LUKS_NAME}" 2>/dev/null || {
        log "cryptsetup close failed, trying dmsetup remove"
        dmsetup remove --force "${LUKS_NAME}" 2>/dev/null || true
    }
    if [[ -e "/dev/mapper/${LUKS_NAME}" ]]; then
        log "WARNING: /dev/mapper/${LUKS_NAME} still exists — may need reboot"
    else
        log "LUKS mapping closed"
    fi
fi

# ---- Detach loop devices pointing at our image ----
if [[ -f "${IMG_RAW}" ]]; then
    for ld in $(losetup -j "${IMG_RAW}" 2>/dev/null | cut -d: -f1); do
        log "Detaching loop device ${ld}"
        losetup -d "${ld}" 2>/dev/null || true
    done
fi

# ---- Also detach any orphaned loops for images that no longer exist ----
for ld in $(losetup -l -n -O NAME,BACK-FILE 2>/dev/null | grep "logos-vm.raw" | awk '{print $1}'); do
    log "Detaching orphaned loop device ${ld}"
    losetup -d "${ld}" 2>/dev/null || true
done

# ---- Remove build artifacts ----
if [[ -d "${WORK_DIR}" ]]; then
    log "Removing build artifacts"

    # Images
    for f in "${WORK_DIR}"/logos-vm.raw "${WORK_DIR}"/logos-vm.qcow2; do
        if [[ -f "${f}" ]]; then
            log "  rm ${f} ($(du -sh "${f}" | cut -f1))"
            rm -f "${f}"
        fi
    done

    # Mount tree
    if [[ -d "${MNT}" ]]; then
        log "  rm -rf ${MNT}"
        rm -rf "${MNT}"
    fi

    # Stage3 cache
    if [[ "${WIPE_CACHE}" == true ]] && [[ -d "${WORK_DIR}/stage3-cache" ]]; then
        log "  rm -rf stage3-cache ($(du -sh "${WORK_DIR}/stage3-cache" | cut -f1))"
        rm -rf "${WORK_DIR}/stage3-cache"
    fi

    # Remove build dir if empty (or only stage3-cache remains)
    rmdir "${WORK_DIR}" 2>/dev/null || true
fi

# ---- Remove logs ----
if [[ -d "${LOG_DIR}" ]]; then
    log "Removing logs"
    rm -rf "${LOG_DIR}"
fi

log "Clean complete."
if [[ "${WIPE_CACHE}" == false ]] && [[ -d "${WORK_DIR}/stage3-cache" ]]; then
    log "Stage3 cache preserved ($(du -sh "${WORK_DIR}/stage3-cache" | cut -f1)). Use --all to remove."
fi
