#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root."
  exit 1
fi

log() { echo "[phase3] $*"; }
install_pkgs() { pacman -S --noconfirm --needed "$@"; }

log "Installing KDE Plasma desktop"
install_pkgs plasma-meta kde-applications-meta sddm packagekit-qt6
systemctl enable sddm.service

log "Installing GPU drivers (auto-detect)"
if command -v lspci >/dev/null 2>&1; then
  if lspci | grep -qi nvidia; then
    install_pkgs nvidia nvidia-utils nvidia-settings nvidia-lts
  fi
  if lspci | grep -qi "amd.*vga\|radeon"; then
    install_pkgs mesa vulkan-radeon libva-mesa-driver
  fi
  if lspci | grep -qi "intel.*vga\|intel.*graphics"; then
    install_pkgs mesa vulkan-intel intel-media-driver
  fi
else
  log "lspci not found; install pciutils if GPU detection is needed."
fi

ensure_yay() {
  local aur_user
  aur_user="${AUR_USER:-${SUDO_USER:-}}"
  if [[ -z "${aur_user}" ]]; then
    echo "Set AUR_USER=<username> to install AUR packages." >&2
    exit 1
  fi

  if command -v yay >/dev/null 2>&1; then
    return 0
  fi

  log "Installing yay for AUR support"
  install_pkgs git base-devel
  runuser -u "${aur_user}" -- bash -c 'set -euo pipefail; tmpdir=$(mktemp -d); cd "$tmpdir"; git clone https://aur.archlinux.org/yay.git; cd yay; makepkg -si --noconfirm; cd /; rm -rf "$tmpdir"'
}

install_office() {
  install_pkgs libreoffice-fresh thunderbird firefox chromium obsidian zotero
}

install_engineering() {
  install_pkgs freecad openscad kicad blender
  ensure_yay
  runuser -u "${AUR_USER:-${SUDO_USER:-}}" -- yay -S --noconfirm autodesk-fusion360 prusa-slicer
}

install_dev() {
  install_pkgs code git python python-pip nodejs npm docker docker-compose
  systemctl enable docker.service
  if [[ -n "${SUDO_USER:-}" ]]; then
    usermod -aG docker "${SUDO_USER}"
  fi
}

install_security() {
  install_pkgs wireshark-qt nmap tcpdump aircrack-ng john hashcat
  ensure_yay
  runuser -u "${AUR_USER:-${SUDO_USER:-}}" -- yay -S --noconfirm metasploit burpsuite
}

install_radio() {
  install_pkgs gqrx gnuradio direwolf xastir fldigi
  ensure_yay
  runuser -u "${AUR_USER:-${SUDO_USER:-}}" -- yay -S --noconfirm sdrangel chirp
}

install_gaming() {
  install_pkgs steam lutris wine winetricks gamemode mangohud
}

install_media() {
  install_pkgs vlc mpv obs-studio kdenlive gimp inkscape audacity
}

if [[ "${INSTALL_OFFICE:-0}" == "1" ]]; then
  log "Installing office and productivity apps"
  install_office
fi

if [[ "${INSTALL_ENGINEERING:-0}" == "1" ]]; then
  log "Installing engineering and CAD apps"
  install_engineering
fi

if [[ "${INSTALL_DEV:-0}" == "1" ]]; then
  log "Installing development tools"
  install_dev
fi

if [[ "${INSTALL_SECURITY:-0}" == "1" ]]; then
  log "Installing security and networking tools"
  install_security
fi

if [[ "${INSTALL_RADIO:-0}" == "1" ]]; then
  log "Installing radio and SAR tools"
  install_radio
fi

if [[ "${INSTALL_GAMING:-0}" == "1" ]]; then
  log "Installing gaming stack"
  install_gaming
fi

if [[ "${INSTALL_MEDIA:-0}" == "1" ]]; then
  log "Installing multimedia stack"
  install_media
fi

log "Phase 3 complete. Reboot to start the desktop."
