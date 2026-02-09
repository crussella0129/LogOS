#!/usr/bin/env bash
# clean.sh — One-shot kill: wipe all build artifacts for a fresh installer run
#
# Kills every process holding our devices, unmounts automounts, closes all
# LUKS/dm mappings (current + legacy NBD-based names), disconnects NBD,
# detaches loop devices, and removes build output.
# Stage3 cache is preserved by default (use --all to remove it too).
#
# Usage: sudo ./installer/clean.sh [--all]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}/build"
IMG_RAW="${WORK_DIR}/logos-vm.raw"
MNT="${WORK_DIR}/mnt"
LOG_DIR="${SCRIPT_DIR}/logs"

# All dm names we have ever used (current losetup-based + old NBD-based)
DM_NAMES=(cryptroot logos-build logos-build-crypt logos-build-new)

log() { echo "[clean $(date +%H:%M:%S)] $*"; }

[[ "$(id -u)" -eq 0 ]] || { echo "Must run as root"; exit 1; }

WIPE_CACHE=false
if [[ "${1:-}" == "--all" ]]; then
    WIPE_CACHE=true
fi

# ---- Freeze udev so automounter cannot re-grab devices during teardown ----
log "Freezing udev event processing"
udevadm control --stop-exec-queue 2>/dev/null || true
# Ensure we always thaw udev on exit, even if we die mid-cleanup
trap 'udevadm control --start-exec-queue 2>/dev/null || true' EXIT

# ---- Helper: kill all processes holding a device ----
kill_holders() {
    local dev="$1"
    [[ -e "${dev}" ]] || return 0
    if fuser -k "${dev}" 2>/dev/null; then
        log "  Killed processes holding ${dev}"
        sleep 0.5
    fi
}

# ---- Helper: force-remove a dm mapping through escalating methods ----
force_close_dm() {
    local name="$1"
    [[ -e "/dev/mapper/${name}" ]] || return 0

    log "Closing dm mapping '${name}'"

    # Kill holders and unmount anything mounted from this device
    kill_holders "/dev/mapper/${name}"
    for mp in $(findmnt -n -o TARGET -S "/dev/mapper/${name}" 2>/dev/null || true); do
        log "  umount ${mp}"
        umount -l "${mp}" 2>/dev/null || true
    done

    # Escalation ladder: cryptsetup → dmsetup --force → wipe_table → remove
    cryptsetup close "${name}" 2>/dev/null && { log "  Closed (cryptsetup)"; return 0; }
    dmsetup remove --force --retry "${name}" 2>/dev/null && { sleep 0.5; }
    [[ -e "/dev/mapper/${name}" ]] || { log "  Closed (dmsetup)"; return 0; }
    dmsetup wipe_table "${name}" 2>/dev/null || true
    dmsetup remove --force "${name}" 2>/dev/null || true
    sleep 0.5
    [[ -e "/dev/mapper/${name}" ]] || { log "  Closed (wipe+remove)"; return 0; }

    log "  WARNING: /dev/mapper/${name} persists — will retry after device detach"
}

# ---- Unmount everything under MNT ----
if mount | grep -q "${MNT}"; then
    log "Unmounting filesystems under ${MNT}"
    for mp in $(mount | grep "${MNT}" | awk '{print $3}' | sort -r); do
        log "  umount ${mp}"
        umount -l "${mp}" 2>/dev/null || true
    done
fi

# ---- Unmount any automounted partitions outside our tree ----
# Ubuntu/Nautilus automounts loop partitions and LUKS to /media/root/* etc.
for dev_path in /dev/mapper/cryptroot /dev/mapper/logos-build* /dev/loop*p* /dev/nbd0p*; do
    [[ -e "${dev_path}" ]] || continue
    mp=$(findmnt -n -o TARGET "${dev_path}" 2>/dev/null || true)
    if [[ -n "${mp}" ]]; then
        log "Unmounting automounted ${dev_path} from ${mp}"
        kill_holders "${dev_path}"
        umount -l "${mp}" 2>/dev/null || true
    fi
done

# ---- Close all dm mappings (current + legacy) ----
for dm in "${DM_NAMES[@]}"; do
    force_close_dm "${dm}"
done

# ---- Disconnect NBD devices (legacy installer) ----
for nbd in /dev/nbd[0-9]*; do
    [[ -b "${nbd}" ]] || continue
    # Skip if no partitions (not connected)
    if lsblk -n -o SIZE "${nbd}" 2>/dev/null | grep -qv '0B'; then
        log "Disconnecting NBD device ${nbd}"
        for part in "${nbd}"p*; do
            [[ -e "${part}" ]] && kill_holders "${part}"
        done
        kill_holders "${nbd}"
        qemu-nbd --disconnect "${nbd}" 2>/dev/null || true
    fi
done

# ---- Detach loop devices pointing at our image ----
if [[ -f "${IMG_RAW}" ]]; then
    for ld in $(losetup -j "${IMG_RAW}" 2>/dev/null | cut -d: -f1); do
        for part in "${ld}"p*; do
            [[ -e "${part}" ]] && kill_holders "${part}"
        done
        kill_holders "${ld}"
        log "Detaching loop device ${ld}"
        losetup -d "${ld}" 2>/dev/null || true
    done
fi

# ---- Detach any orphaned loops (image deleted but loop still attached) ----
for ld in $(losetup -l -n -O NAME,BACK-FILE 2>/dev/null | grep "logos-vm" | awk '{print $1}'); do
    for part in "${ld}"p*; do
        [[ -e "${part}" ]] && kill_holders "${part}"
    done
    kill_holders "${ld}"
    log "Detaching orphaned loop device ${ld}"
    losetup -d "${ld}" 2>/dev/null || true
done

# ---- Final sweep: retry any dm mappings that persisted ----
any_stuck=false
for dm in "${DM_NAMES[@]}"; do
    if [[ -e "/dev/mapper/${dm}" ]]; then
        sleep 1
        dmsetup remove --force "${dm}" 2>/dev/null || true
        if [[ -e "/dev/mapper/${dm}" ]]; then
            log "ERROR: /dev/mapper/${dm} is stuck. Reboot required."
            any_stuck=true
        else
            log "Stale dm entry '${dm}' cleared after device detach"
        fi
    fi
done

# ---- Remove build artifacts ----
if [[ -d "${WORK_DIR}" ]]; then
    log "Removing build artifacts"

    for f in "${WORK_DIR}"/logos-vm.raw "${WORK_DIR}"/logos-vm.qcow2; do
        if [[ -f "${f}" ]]; then
            log "  rm ${f} ($(du -sh "${f}" | cut -f1))"
            rm -f "${f}"
        fi
    done

    if [[ -d "${MNT}" ]]; then
        log "  rm -rf ${MNT}"
        rm -rf "${MNT}"
    fi

    if [[ "${WIPE_CACHE}" == true ]] && [[ -d "${WORK_DIR}/stage3-cache" ]]; then
        log "  rm -rf stage3-cache ($(du -sh "${WORK_DIR}/stage3-cache" | cut -f1))"
        rm -rf "${WORK_DIR}/stage3-cache"
    fi

    rmdir "${WORK_DIR}" 2>/dev/null || true
fi

# ---- Remove logs ----
if [[ -d "${LOG_DIR}" ]]; then
    log "Removing logs"
    rm -rf "${LOG_DIR}"
fi

# ---- Also clean test-vm/ debris if present ----
if [[ -d "${SCRIPT_DIR}/../test-vm" ]]; then
    log "Removing legacy test-vm/"
    rm -rf "${SCRIPT_DIR}/../test-vm"
fi

# ---- Resume udev ----
log "Resuming udev event processing"
udevadm control --start-exec-queue 2>/dev/null || true

if [[ "${any_stuck}" == true ]]; then
    log "Clean finished with warnings — reboot to clear stuck dm entries."
else
    log "Clean complete."
fi
if [[ "${WIPE_CACHE}" == false ]] && [[ -d "${WORK_DIR}/stage3-cache" ]]; then
    log "Stage3 cache preserved ($(du -sh "${WORK_DIR}/stage3-cache" | cut -f1)). Use --all to remove."
fi
