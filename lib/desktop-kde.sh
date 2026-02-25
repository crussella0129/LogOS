#!/usr/bin/env bash
# lib/desktop-kde.sh — KDE Plasma desktop module
# Extracted from the original scripts/06-desktop.sh.
# Provides install_kde() and configure_kde() called by the dispatcher.

readonly KDE_PACKAGES=(
  plasma-meta
  kde-applications-meta
  sddm
  packagekit-qt6
)

install_kde() {
  log "Installing KDE Plasma"
  install_pkgs "${KDE_PACKAGES[@]}"

  local terminal
  terminal="$(resolve_terminal kde)"
  if [[ -n "${terminal}" ]]; then
    install_pkgs "${terminal}"
  fi
}

configure_kde() {
  configure_sddm
  deploy_desktop_dotfiles kde
  log_ok "KDE Plasma configured"
}
