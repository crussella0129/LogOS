#!/usr/bin/env bash
# 00-verify-env.sh — Live Environment Check
# Context: Run from the Arch Linux live USB, before any disk operations.
# Verifies UEFI mode, network, clock sync, pacman keyring, and mirrors.

LOGOS_SECTION="00-verify"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/detect.sh"

require_root
require_live_env

# ── UEFI mode ───────────────────────────────────────────────────────
log "Checking boot mode"
if is_uefi; then
  log_ok "UEFI boot mode confirmed"
else
  log_err "System booted in legacy BIOS mode."
  log_err "LogOS requires UEFI. Reboot and enable UEFI in firmware settings."
  exit 1
fi

# ── Network connectivity ────────────────────────────────────────────
log "Checking network connectivity"
if ping -c 1 -W 5 archlinux.org >/dev/null 2>&1; then
  log_ok "Network is reachable"
else
  log_err "No network connectivity. Connect via ethernet or iwctl."
  exit 1
fi

# ── System clock ────────────────────────────────────────────────────
log "Synchronizing system clock"
timedatectl set-ntp true
sleep 2
if timedatectl status | grep -q "synchronized: yes"; then
  log_ok "Clock synchronized via NTP"
else
  log_warn "NTP sync not confirmed — clock may drift"
fi

# ── Pacman keyring ──────────────────────────────────────────────────
log "Refreshing pacman keyring"
pacman-key --init
pacman-key --populate archlinux
pacman -Sy --noconfirm archlinux-keyring
log_ok "Keyring refreshed"

# ── Mirror optimization (optional) ─────────────────────────────────
load_config "${SCRIPT_DIR}/../logos.conf" || true

if [[ -n "${LOGOS_MIRROR_COUNTRY:-}" ]]; then
  log "Optimizing mirrors for ${LOGOS_MIRROR_COUNTRY}"
  if command -v reflector >/dev/null 2>&1 || pacman -S --noconfirm reflector; then
    reflector --country "${LOGOS_MIRROR_COUNTRY}" \
              --protocol https \
              --sort rate \
              --latest 10 \
              --save /etc/pacman.d/mirrorlist
    log_ok "Mirrors optimized"
  fi
else
  log "Skipping mirror optimization (LOGOS_MIRROR_COUNTRY not set)"
fi

# ── Configuration summary ──────────────────────────────────────────
if [[ -f "${SCRIPT_DIR}/../logos.conf" ]]; then
  echo ""
  echo "════════════════════════════════════════════════════════════"
  echo "  LogOS Build Configuration Summary"
  echo "════════════════════════════════════════════════════════════"
  echo "  Disk:       ${LOGOS_DISK:-not set}"
  echo "  Hostname:   ${LOGOS_HOSTNAME:-not set}"
  echo "  Username:   ${LOGOS_USERNAME:-not set}"
  echo "  Timezone:   ${LOGOS_TIMEZONE:-not set}"
  echo "  Encryption: $([ "${LOGOS_ENCRYPT:-1}" = "1" ] && echo "LUKS2 + ${LOGOS_LUKS_PBKDF:-argon2id}" || echo "DISABLED")"
  echo "  Hardened:   $([ "${LOGOS_ENABLE_HARDENED:-0}" = "1" ] && echo "yes" || echo "no")"
  echo "  Profiles:   $([ "${LOGOS_PROFILE_GAEL:-1}" = "1" ] && echo "Gael ")$([ "${LOGOS_PROFILE_MIDIR:-1}" = "1" ] && echo "Midir ")$([ "${LOGOS_PROFILE_HALFLIGHT:-1}" = "1" ] && echo "Halflight")"
  echo "════════════════════════════════════════════════════════════"
  echo ""

  # Show available disks for reference
  log "Available disks:"
  detect_disks
  echo ""
else
  log_warn "logos.conf not found — copy logos.conf.example and edit it"
fi

log_ok "Live environment verified and ready"
