#!/usr/bin/env bash
# lib/desktop-sway.sh — Sway desktop module
# Sway: i3-compatible Wayland compositor.
# Provides install_sway() and configure_sway() called by the dispatcher.

readonly SWAY_PACKAGES=(
  sway
  xdg-desktop-portal-wlr
  waybar
  rofi-wayland
  mako
  grim
  slurp
  wl-clipboard
  cliphist
  swaylock
  swaybg
  polkit-gnome
  qt5-wayland
  qt6-wayland
)

install_sway() {
  log "Installing Sway compositor"
  install_pkgs "${SWAY_PACKAGES[@]}"

  local terminal
  terminal="$(resolve_terminal sway)"
  if [[ -n "${terminal}" ]]; then
    install_pkgs "${terminal}"
  fi
}

configure_sway() {
  configure_greetd sway
  deploy_desktop_dotfiles sway
  log_ok "Sway configured"
}
