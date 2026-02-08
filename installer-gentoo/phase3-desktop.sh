#!/usr/bin/env bash
# LogOS Gentoo — Phase 3: Desktop Environment & Optional Packages
# KDE Plasma, GPU detection, modular package categories
#
# Run on booted system as root.
# Prerequisites: Phase 2 completed, system rebooted
#
# Usage: INSTALL_OFFICE=1 INSTALL_DEV=1 ./phase3-desktop.sh
#
# Environment variables (set to 1 to enable):
#   INSTALL_OFFICE       — LibreOffice, Thunderbird, Firefox, Obsidian
#   INSTALL_ENGINEERING  — FreeCAD, OpenSCAD, KiCAD, Blender
#   INSTALL_DEV          — VS Code, Git, Python, Node.js, Docker
#   INSTALL_SECURITY     — Wireshark, nmap, hashcat, metasploit (overlay)
#   INSTALL_RADIO        — GQRX, GNURadio, Direwolf, FLDIGI
#   INSTALL_GAMING       — Steam, Lutris, Wine, GameMode
#   INSTALL_MEDIA        — VLC, OBS, Kdenlive, GIMP, Inkscape
#   INSTALL_SDR          — Extended SDR tooling (gnuradio, hackrf, soapysdr)
#   INSTALL_SPECTRAL     — Spectral analysis (fftw, scipy, sonic-visualiser)
#   INSTALL_RUST_TOOLS   — Additional Rust CLI tools

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/portage.sh"

require_root

# ── KDE Plasma Desktop ───────────────────────────────────────────
log "Installing KDE Plasma desktop"
emerge_pkgs kde-plasma/plasma-meta x11-misc/sddm kde-apps/kde-apps-meta
systemctl enable sddm.service

# ── GPU Auto-Detection ────────────────────────────────────────────
log "Detecting GPU hardware"
if command -v lspci >/dev/null 2>&1; then
  GPU_DETECTED=""

  if lspci | grep -qi nvidia; then
    log "  NVIDIA GPU detected"
    GPU_DETECTED="nvidia"
    emerge_pkgs x11-drivers/nvidia-drivers
    # Update make.conf
    if ! grep -q 'VIDEO_CARDS.*nvidia' /etc/portage/make.conf; then
      echo 'VIDEO_CARDS="nvidia"' >> /etc/portage/make.conf
    fi
  fi

  if lspci | grep -qi "amd.*vga\|radeon\|amdgpu"; then
    log "  AMD GPU detected"
    GPU_DETECTED="amd"
    emerge_pkgs media-libs/mesa x11-drivers/xf86-video-amdgpu
    if ! grep -q 'VIDEO_CARDS.*amdgpu' /etc/portage/make.conf; then
      echo 'VIDEO_CARDS="amdgpu radeonsi"' >> /etc/portage/make.conf
    fi
  fi

  if lspci | grep -qi "intel.*vga\|intel.*graphics"; then
    log "  Intel GPU detected"
    GPU_DETECTED="intel"
    emerge_pkgs media-libs/mesa media-libs/intel-media-driver
    if ! grep -q 'VIDEO_CARDS.*intel' /etc/portage/make.conf; then
      echo 'VIDEO_CARDS="intel"' >> /etc/portage/make.conf
    fi
  fi

  if [[ -z "${GPU_DETECTED}" ]]; then
    log "  No discrete GPU detected — using framebuffer"
  fi
else
  warn "lspci not found — install sys-apps/pciutils if GPU detection is needed"
  emerge_pkgs sys-apps/pciutils
fi

# ── Optional Package Categories ──────────────────────────────────

if [[ "${INSTALL_OFFICE:-0}" == "1" ]]; then
  log "Installing office and productivity apps"
  emerge_pkgs app-office/libreoffice \
              mail-client/thunderbird \
              www-client/firefox \
              www-client/chromium
  # Obsidian and Zotero — may need overlay
  emerge_pkgs app-text/zotero 2>/dev/null || warn "zotero not in tree — add to logos-overlay"
fi

if [[ "${INSTALL_ENGINEERING:-0}" == "1" ]]; then
  log "Installing engineering and CAD apps"
  emerge_pkgs media-gfx/freecad \
              media-gfx/openscad \
              sci-electronics/kicad \
              media-gfx/blender
  emerge_pkgs media-gfx/prusaslicer 2>/dev/null || warn "prusaslicer not in tree — check overlay"
fi

if [[ "${INSTALL_DEV:-0}" == "1" ]]; then
  log "Installing development tools"
  emerge_pkgs app-editors/vscode \
              dev-vcs/git \
              dev-lang/python \
              net-libs/nodejs \
              app-containers/docker \
              app-containers/docker-compose
  systemctl enable docker.service
  if [[ -n "${SUDO_USER:-}" ]]; then
    usermod -aG docker "${SUDO_USER}"
  fi
fi

if [[ "${INSTALL_SECURITY:-0}" == "1" ]]; then
  log "Installing security and networking tools"
  emerge_pkgs net-analyzer/wireshark \
              net-analyzer/nmap \
              net-analyzer/tcpdump \
              net-wireless/aircrack-ng \
              app-crypt/john \
              app-crypt/hashcat

  # Pentoo overlay for metasploit, burpsuite
  ensure_eselect_repository
  add_overlay pentoo "https://github.com/pentoo/pentoo-overlay.git"
  emerge_pkgs net-analyzer/metasploit 2>/dev/null || warn "metasploit: enable pentoo overlay"
fi

if [[ "${INSTALL_RADIO:-0}" == "1" ]]; then
  log "Installing radio and SAR tools"
  emerge_pkgs net-wireless/gnuradio \
              net-wireless/gqrx \
              media-radio/direwolf \
              media-radio/fldigi \
              sci-geosciences/xastir
fi

if [[ "${INSTALL_GAMING:-0}" == "1" ]]; then
  log "Installing gaming stack"
  emerge_pkgs games-util/steam-launcher \
              games-util/lutris \
              app-emulation/wine-staging \
              app-emulation/winetricks \
              games-util/gamemode \
              games-util/mangohud
fi

if [[ "${INSTALL_MEDIA:-0}" == "1" ]]; then
  log "Installing multimedia stack"
  emerge_pkgs media-video/vlc \
              media-video/mpv \
              media-video/obs-studio \
              kde-apps/kdenlive \
              media-gfx/gimp \
              media-gfx/inkscape \
              media-sound/audacity
fi

# ── New Feature Categories (Gentoo-specific) ─────────────────────

if [[ "${INSTALL_SDR:-0}" == "1" ]]; then
  log "Installing extended SDR tooling"
  emerge_pkgs net-wireless/gnuradio \
              net-wireless/gqrx \
              net-wireless/rtl-sdr \
              net-wireless/hackrf-tools \
              net-wireless/soapysdr
  emerge_pkgs net-wireless/sdrangel 2>/dev/null || warn "sdrangel not in tree — add to logos-overlay"
fi

if [[ "${INSTALL_SPECTRAL:-0}" == "1" ]]; then
  log "Installing spectral analysis tools"
  emerge_pkgs sci-libs/fftw \
              dev-python/scipy \
              dev-python/numpy \
              media-sound/sonic-visualiser
fi

if [[ "${INSTALL_RUST_TOOLS:-0}" == "1" ]]; then
  log "Installing additional Rust CLI tools"
  emerge_pkgs sys-apps/ripgrep sys-apps/fd sys-apps/bat \
              app-misc/eza sys-process/bottom \
              app-shells/starship dev-util/tokei \
              sys-apps/dust app-shells/zoxide \
              net-analyzer/bandwhich sys-process/procs \
    || warn "Some Rust tools not available — check overlay"
fi

log "Phase 3 complete. Reboot to start the desktop."
