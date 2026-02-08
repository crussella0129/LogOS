#!/usr/bin/env bash
# clean.sh — One-shot kill: wipe all build artifacts for a fresh installer run
#
# Force-kills any process holding our LUKS/loop devices, stops udisks
# automounting, closes LUKS, detaches loops, removes build output.
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

# ---- Kill udisks polling on our devices ----
# Ubuntu's automounter (udisksd/nautilus) grabs loop partitions and LUKS
# devices the moment they appear, preventing cryptsetup close. Kill any
# udisks job targeting our devices before attempting cleanup.
kill_holders() {
    local dev="$1"
    if [[ ! -e "${dev}" ]]; then return; fi
    # fuser returns PIDs holding the device; -k sends SIGKILL
    if fuser -k "${dev}" 2>/dev/null; then
        log "  Killed processes holding ${dev}"
        sleep 0.5
    fi
}

# ---- Unmount everything under MNT ----
if mount | grep -q "${MNT}"; then
    log "Unmounting filesystems under ${MNT}"
    for mp in $(mount | grep "${MNT}" | awk '{print $3}' | sort -r); do
        log "  umount ${mp}"
        umount -l "${mp}" 2>/dev/null || true
    done
fi

# ---- Unmount any automounted LUKS/loop partitions outside our tree ----
# Ubuntu may automount the btrfs/ext4 partitions to /media/root/* or similar
for dev_path in /dev/mapper/"${LUKS_NAME}" /dev/loop*p*; do
    if [[ -e "${dev_path}" ]]; then
        mp=$(findmnt -n -o TARGET "${dev_path}" 2>/dev/null || true)
        if [[ -n "${mp}" ]]; then
            log "Unmounting automounted ${dev_path} from ${mp}"
            umount -l "${mp}" 2>/dev/null || true
        fi
    fi
done

# ---- Close LUKS ----
if [[ -e "/dev/mapper/${LUKS_NAME}" ]]; then
    log "Closing LUKS mapping '${LUKS_NAME}'"

    # Kill anything holding the mapper device open (nautilus, udisksd, etc)
    kill_holders "/dev/mapper/${LUKS_NAME}"

    # Also kill holders of the underlying btrfs mount if still referenced
    for mp in $(findmnt -n -o TARGET -S "/dev/mapper/${LUKS_NAME}" 2>/dev/null || true); do
        umount -l "${mp}" 2>/dev/null || true
    done

    # Attempt 1: cryptsetup
    if cryptsetup close "${LUKS_NAME}" 2>/dev/null; then
        log "LUKS mapping closed (cryptsetup)"
    else
        # Attempt 2: dmsetup with --force and deferred removal
        log "cryptsetup close failed, forcing with dmsetup"
        dmsetup remove --force --retry "${LUKS_NAME}" 2>/dev/null || true
        sleep 1

        # Attempt 3: deactivate all children first, then parent
        if [[ -e "/dev/mapper/${LUKS_NAME}" ]]; then
            # Some dm devices stack; remove children
            for child in $(dmsetup ls --tree 2>/dev/null | grep -A1 "${LUKS_NAME}" | grep -v "${LUKS_NAME}" | awk '{print $1}'); do
                dmsetup remove --force "${child}" 2>/dev/null || true
            done
            dmsetup remove --force "${LUKS_NAME}" 2>/dev/null || true
            sleep 1
        fi

        if [[ -e "/dev/mapper/${LUKS_NAME}" ]]; then
            # Final attempt: wipe the dm table so the device becomes inert
            dmsetup wipe_table "${LUKS_NAME}" 2>/dev/null || true
            dmsetup remove --force "${LUKS_NAME}" 2>/dev/null || true
            sleep 1
        fi
    fi

    if [[ -e "/dev/mapper/${LUKS_NAME}" ]]; then
        log "WARNING: /dev/mapper/${LUKS_NAME} still exists"
        log "  Likely held by a kernel reference. Will detach loop device anyway."
        log "  The dm entry will disappear once the loop device is gone."
    fi
fi

# ---- Detach loop devices pointing at our image ----
if [[ -f "${IMG_RAW}" ]]; then
    for ld in $(losetup -j "${IMG_RAW}" 2>/dev/null | cut -d: -f1); do
        # Kill anything holding loop partitions (automounter)
        for part in "${ld}"p*; do
            [[ -e "${part}" ]] && kill_holders "${part}"
        done
        kill_holders "${ld}"
        log "Detaching loop device ${ld}"
        losetup -d "${ld}" 2>/dev/null || true
    done
fi

# ---- Also detach any orphaned loops (image deleted but loop still attached) ----
for ld in $(losetup -l -n -O NAME,BACK-FILE 2>/dev/null | grep "logos-vm.raw" | awk '{print $1}'); do
    for part in "${ld}"p*; do
        [[ -e "${part}" ]] && kill_holders "${part}"
    done
    kill_holders "${ld}"
    log "Detaching orphaned loop device ${ld}"
    losetup -d "${ld}" 2>/dev/null || true
done

# ---- Final dm cleanup: catch any stale cryptroot after loop detach ----
if [[ -e "/dev/mapper/${LUKS_NAME}" ]]; then
    sleep 1
    dmsetup remove --force "${LUKS_NAME}" 2>/dev/null || true
    if [[ -e "/dev/mapper/${LUKS_NAME}" ]]; then
        log "ERROR: /dev/mapper/${LUKS_NAME} is stuck. Reboot required."
    else
        log "Stale dm entry cleared after loop detach"
    fi
fi

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
