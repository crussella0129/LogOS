#!/usr/bin/env bash
# 06-desktop.sh — Desktop Environment Dispatcher
# Context: Run on the booted system after first reboot.
# Reads LOGOS_DESKTOP and LOGOS_THEME from config, sources the appropriate
# desktop module, and deploys themed dotfiles.
#
# Supported desktops: hyprland (default), kde, sway, i3
# Supported themes:   ringed-city (default), catppuccin-mocha, dracula

LOGOS_SECTION="06-desktop"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f /root/LogOS/lib/common.sh ]]; then
  source /root/LogOS/lib/common.sh
  source /root/LogOS/lib/detect.sh
  source /root/LogOS/lib/desktop.sh
  load_config /root/LogOS/logos.conf
else
  source "${SCRIPT_DIR}/../lib/common.sh"
  source "${SCRIPT_DIR}/../lib/detect.sh"
  source "${SCRIPT_DIR}/../lib/desktop.sh"
  load_config "${SCRIPT_DIR}/../logos.conf"
fi

require_root

# ── Resolve desktop and theme ────────────────────────────────────────
DESKTOP="${LOGOS_DESKTOP:-hyprland}"
THEME="${LOGOS_THEME:-ringed-city}"

case "${DESKTOP}" in
  hyprland|kde|sway|i3) ;;
  *)
    log_err "Invalid desktop: ${DESKTOP}"
    log_err "Valid options: hyprland, kde, sway, i3"
    exit 1
    ;;
esac

case "${THEME}" in
  ringed-city|catppuccin-mocha|dracula) ;;
  *)
    log_err "Invalid theme: ${THEME}"
    log_err "Valid options: ringed-city, catppuccin-mocha, dracula"
    exit 1
    ;;
esac

log "Desktop: ${DESKTOP} | Theme: ${THEME}"

# ── Load theme ───────────────────────────────────────────────────────
load_theme "${THEME}"

# ── Source desktop module ────────────────────────────────────────────
DESKTOP_MODULE=""
if [[ -f "/root/LogOS/lib/desktop-${DESKTOP}.sh" ]]; then
  DESKTOP_MODULE="/root/LogOS/lib/desktop-${DESKTOP}.sh"
elif [[ -f "${SCRIPT_DIR}/../lib/desktop-${DESKTOP}.sh" ]]; then
  DESKTOP_MODULE="${SCRIPT_DIR}/../lib/desktop-${DESKTOP}.sh"
else
  log_err "Desktop module not found: desktop-${DESKTOP}.sh"
  exit 1
fi

# shellcheck source=/dev/null
source "${DESKTOP_MODULE}"
log "Loaded module: ${DESKTOP_MODULE}"

# ── Install shared packages ─────────────────────────────────────────
install_shared_packages
install_gpu_drivers

# ── Install and configure desktop ────────────────────────────────────
install_"${DESKTOP}"
configure_"${DESKTOP}"

# ── Deploy shared dotfiles ───────────────────────────────────────────
deploy_shared_dotfiles

log_ok "Desktop environment installed (${DESKTOP} + ${THEME}). Reboot to start."
