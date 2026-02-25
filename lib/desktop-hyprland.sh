#!/usr/bin/env bash
# lib/desktop-hyprland.sh — Hyprland desktop module
# The default "cyberdeck superfluid" experience.
# Provides install_hyprland() and configure_hyprland() called by the dispatcher.

readonly HYPRLAND_PACKAGES=(
  hyprland
  xdg-desktop-portal-hyprland
  hyprpaper
  hyprlock
  waybar
  rofi-wayland
  dunst
  grim
  slurp
  wl-clipboard
  cliphist
  polkit-gnome
  qt5-wayland
  qt6-wayland
)

install_hyprland() {
  log "Installing Hyprland compositor"
  install_pkgs "${HYPRLAND_PACKAGES[@]}"

  local terminal
  terminal="$(resolve_terminal hyprland)"
  if [[ -n "${terminal}" ]]; then
    install_pkgs "${terminal}"
  fi
}

configure_hyprland() {
  # NVIDIA environment variables for Wayland
  mapfile -t gpus < <(detect_gpu)
  for gpu in "${gpus[@]}"; do
    if [[ "${gpu}" == "nvidia" ]]; then
      log "Configuring NVIDIA Wayland environment"
      mkdir -p /etc/environment.d
      cat > /etc/environment.d/logos-nvidia.conf <<'NVEOF'
LIBVA_DRIVER_NAME=nvidia
__GLX_VENDOR_LIBRARY_NAME=nvidia
WLR_NO_HARDWARE_CURSORS=1
NVEOF
      log_ok "NVIDIA Wayland vars written to /etc/environment.d/logos-nvidia.conf"
      break
    fi
  done

  # Login manager
  configure_greetd Hyprland

  # Deploy Hyprland dotfiles
  deploy_desktop_dotfiles hyprland

  log_ok "Hyprland configured"
}
