#!/usr/bin/env bash
# lib/desktop-i3.sh — i3 desktop module
# i3: X11 tiling window manager.
# Provides install_i3() and configure_i3() called by the dispatcher.

readonly I3_PACKAGES=(
  i3-wm
  i3status
  polybar
  rofi
  dmenu
  dunst
  xorg-server
  xorg-xinit
  xclip
  picom
  feh
)

install_i3() {
  log "Installing i3 window manager"
  install_pkgs "${I3_PACKAGES[@]}"

  local terminal
  terminal="$(resolve_terminal i3)"
  if [[ -n "${terminal}" ]]; then
    install_pkgs "${terminal}"
  fi
}

configure_i3() {
  configure_lightdm
  deploy_desktop_dotfiles i3
  log_ok "i3 configured"
}
