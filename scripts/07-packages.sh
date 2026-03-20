#!/usr/bin/env bash
# 07-packages.sh — Modular Package Categories
# Context: Run on the booted system after 06-desktop.sh.
# Reads LOGOS_PKG_* toggles from logos.conf and installs selected categories.
#
# Ported from: phase3-desktop.sh:31-121 (package functions + yay bootstrap)

LOGOS_SECTION="07-packages"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f /root/LogOS/lib/common.sh ]]; then
  source /root/LogOS/lib/common.sh
  load_config /root/LogOS/logos.conf
else
  source "${SCRIPT_DIR}/../lib/common.sh"
  load_config "${SCRIPT_DIR}/../logos.conf"
fi

require_root

# ── AUR helper (yay) ──────────────────────────────────────────────
ensure_yay() {
  local aur_user="${LOGOS_USERNAME:-${SUDO_USER:-}}"
  if [[ -z "${aur_user}" ]]; then
    log_err "Set LOGOS_USERNAME in logos.conf for AUR package support."
    return 1
  fi

  if command -v yay >/dev/null 2>&1; then
    return 0
  fi

  log "Installing yay (AUR helper)"
  install_pkgs git base-devel
  runuser -u "${aur_user}" -- bash -c '
    set -euo pipefail
    tmpdir=$(mktemp -d)
    cd "${tmpdir}"
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd /
    rm -rf "${tmpdir}"
  '
  log_ok "yay installed"
}

aur_install() {
  local aur_user="${LOGOS_USERNAME:-${SUDO_USER:-}}"
  ensure_yay
  runuser -u "${aur_user}" -- yay -S --noconfirm "$@"
}

# ── Package categories ─────────────────────────────────────────────

if [[ "${LOGOS_PKG_OFFICE:-0}" == "1" ]]; then
  log "Installing: Office & Productivity"
  install_pkgs libreoffice-fresh thunderbird firefox chromium obsidian zotero
fi

if [[ "${LOGOS_PKG_DEV:-0}" == "1" ]]; then
  log "Installing: Development Tools"
  install_pkgs code git python python-pip nodejs npm docker docker-compose docker-openrc
  rc-update add docker default
  if id "${LOGOS_USERNAME}" >/dev/null 2>&1; then
    usermod -aG docker "${LOGOS_USERNAME}"
    log_ok "Added ${LOGOS_USERNAME} to docker group"
  fi
fi

if [[ "${LOGOS_PKG_SECURITY:-0}" == "1" ]]; then
  log "Installing: Security & Networking"
  install_pkgs wireshark-qt nmap tcpdump aircrack-ng john hashcat
  aur_install metasploit burpsuite
fi

if [[ "${LOGOS_PKG_RADIO:-0}" == "1" ]]; then
  log "Installing: Radio & SAR"
  install_pkgs gqrx gnuradio direwolf xastir fldigi
  aur_install sdrangel chirp
fi

if [[ "${LOGOS_PKG_GAMING:-0}" == "1" ]]; then
  log "Installing: Gaming"
  install_pkgs steam lutris wine winetricks gamemode mangohud
fi

if [[ "${LOGOS_PKG_MEDIA:-0}" == "1" ]]; then
  log "Installing: Multimedia"
  install_pkgs vlc mpv obs-studio kdenlive gimp inkscape audacity
fi

if [[ "${LOGOS_PKG_ENGINEERING:-0}" == "1" ]]; then
  log "Installing: Engineering & CAD"
  install_pkgs freecad openscad kicad blender
  aur_install autodesk-fusion360 prusa-slicer
fi

log_ok "Package installation complete. Proceed to 08-knowledge.sh"
