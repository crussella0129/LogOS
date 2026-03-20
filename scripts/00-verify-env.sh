#!/usr/bin/env bash
# 00-verify-env.sh — Live Environment Check
# Context: Run from the Artix Linux live USB, before any disk operations.
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
if ping -c 1 -W 5 artixlinux.org >/dev/null 2>&1; then
  log_ok "Network is reachable"
else
  log_err "No network connectivity. Connect via ethernet or connmanctl/iwctl."
  exit 1
fi

# ── System clock ────────────────────────────────────────────────────
# No timedatectl on Artix (that's systemd). Use ntpd or chrony if available,
# otherwise just sync hardware clock.
log "Synchronizing system clock"
if command -v ntpd >/dev/null 2>&1; then
  ntpd -q -g 2>/dev/null && log_ok "Clock synchronized via ntpd" || log_warn "ntpd sync failed"
elif command -v chronyd >/dev/null 2>&1; then
  chronyc makestep 2>/dev/null && log_ok "Clock synchronized via chrony" || log_warn "chrony sync failed"
elif command -v sntp >/dev/null 2>&1; then
  sntp -S pool.ntp.org 2>/dev/null && log_ok "Clock synchronized via sntp" || log_warn "sntp sync failed"
else
  hwclock --systohc 2>/dev/null || true
  log_warn "No NTP client found — clock may drift. Install ntp or chrony."
fi

# ── Pacman keyring ──────────────────────────────────────────────────
log "Refreshing pacman keyring"
pacman-key --init
pacman-key --populate artix
pacman-key --populate archlinux 2>/dev/null || true
pacman -Sy --noconfirm artix-keyring artix-archlinux-support 2>/dev/null || \
  pacman -Sy --noconfirm artix-keyring
log_ok "Keyring refreshed"

# ── Mirror optimization (optional) ─────────────────────────────────
load_config "${SCRIPT_DIR}/../logos.conf" || true

if [[ -n "${LOGOS_MIRROR_COUNTRY:-}" ]]; then
  log "Mirror optimization for Artix"
  # Artix does not use reflector (that's Arch-specific).
  # Rank Artix mirrors by speed if rankmirrors is available.
  if command -v rankmirrors >/dev/null 2>&1; then
    cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
    rankmirrors -n 6 /etc/pacman.d/mirrorlist.bak > /etc/pacman.d/mirrorlist
    log_ok "Artix mirrors ranked"
  else
    log_warn "rankmirrors not found — using default mirror order"
  fi
else
  log "Skipping mirror optimization (LOGOS_MIRROR_COUNTRY not set)"
fi

# ── Configuration summary ──────────────────────────────────────────
if [[ -f "${SCRIPT_DIR}/../logos.conf" ]]; then
  echo ""
  echo "════════════════════════════════════════════════════════════"
  echo "  LogOS Artix Build Configuration Summary"
  echo "════════════════════════════════════════════════════════════"
  echo "  Base:       Artix Linux (OpenRC)"
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
