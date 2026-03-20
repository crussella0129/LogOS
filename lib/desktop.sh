#!/usr/bin/env bash
# lib/desktop.sh — Shared desktop library
# Provides theme loading, template engine, dotfile deployment, shared packages
# (Pipewire, GPU drivers, fonts), and login manager configuration.
# Sourced by scripts/06-desktop.sh after lib/common.sh and lib/detect.sh.

# ── Theme loading ────────────────────────────────────────────────────
# Source a theme file, making all THEME_* variables available.
# Usage: load_theme <theme-name>
load_theme() {
  local theme="${1:?load_theme requires a theme name}"
  local theme_file

  # Search paths: deployed location first, then repo
  if [[ -f "/root/LogOS/dotfiles/themes/${theme}.sh" ]]; then
    theme_file="/root/LogOS/dotfiles/themes/${theme}.sh"
  elif [[ -f "${LOGOS_ROOT}/dotfiles/themes/${theme}.sh" ]]; then
    theme_file="${LOGOS_ROOT}/dotfiles/themes/${theme}.sh"
  else
    log_err "Theme not found: ${theme}"
    log_err "Available: ringed-city, catppuccin-mocha, dracula"
    return 1
  fi

  # shellcheck source=/dev/null
  source "${theme_file}"
  log_ok "Theme loaded: ${THEME_NAME} (${theme_file})"
}

# ── Template engine ──────────────────────────────────────────────────
# Replace all @@THEME_*@@ placeholders in a file with values from the
# currently loaded theme. Uses '|' as sed delimiter (safe with hex colors).
# Usage: apply_template <input-file> <output-file>
apply_template() {
  local input="${1:?apply_template requires input file}"
  local output="${2:?apply_template requires output file}"

  # Build sed expression from all THEME_* variables
  local sed_expr=""
  local var val
  while IFS='=' read -r var val; do
    # Strip 'declare -- ' prefix from declare -p output variations
    sed_expr="${sed_expr}s|@@${var}@@|${val}|g;"
  done < <(compgen -A variable THEME_ | while read -r v; do
    echo "${v}=${!v}"
  done)

  if [[ -z "${sed_expr}" ]]; then
    log_err "No THEME_* variables loaded — did you call load_theme first?"
    return 1
  fi

  mkdir -p "$(dirname "${output}")"
  sed "${sed_expr}" "${input}" > "${output}"

  # Hyprland-specific: rgb(#aabbcc) → rgb(aabbcc) — Hyprland expects no '#'
  if grep -q 'rgb(#' "${output}" 2>/dev/null; then
    sed -i 's|rgb(#|rgb(|g' "${output}"
  fi

  # Verify no unreplaced placeholders remain
  if grep -q '@@THEME_' "${output}" 2>/dev/null; then
    local remaining
    remaining="$(grep -oP '@@THEME_\w+@@' "${output}" | sort -u | tr '\n' ' ')"
    log_warn "Unreplaced placeholders in ${output}: ${remaining}"
  fi
}

# ── Dotfile deployment ───────────────────────────────────────────────
# Deploy dotfiles from a source directory, applying theme templates.
# Files are installed to the target user's home directory.
# Usage: deploy_dotfiles <source-dir> <target-config-dir>
deploy_dotfiles() {
  local src="${1:?deploy_dotfiles requires source directory}"
  local target="${2:?deploy_dotfiles requires target config directory}"

  if [[ ! -d "${src}" ]]; then
    log_warn "Dotfile source not found: ${src}"
    return 0
  fi

  local file relpath dest
  while IFS= read -r -d '' file; do
    relpath="${file#"${src}/"}"
    dest="${target}/${relpath}"
    mkdir -p "$(dirname "${dest}")"

    if grep -q '@@THEME_' "${file}" 2>/dev/null; then
      apply_template "${file}" "${dest}"
      log "Templated: ${relpath}"
    else
      cp "${file}" "${dest}"
      log "Copied: ${relpath}"
    fi
  done < <(find "${src}" -type f -print0)
}

# ── Shared dotfile deployment ────────────────────────────────────────
# Deploy dotfiles from dotfiles/shared/ to the user's ~/.config/.
# Usage: deploy_shared_dotfiles
deploy_shared_dotfiles() {
  local user="${LOGOS_USERNAME:?LOGOS_USERNAME not set}"
  local home="/home/${user}"
  local shared_src

  if [[ -d "/root/LogOS/dotfiles/shared" ]]; then
    shared_src="/root/LogOS/dotfiles/shared"
  elif [[ -d "${LOGOS_ROOT}/dotfiles/shared" ]]; then
    shared_src="${LOGOS_ROOT}/dotfiles/shared"
  else
    log_warn "No shared dotfiles found — skipping"
    return 0
  fi

  log "Deploying shared dotfiles to ${home}/.config/"
  deploy_dotfiles "${shared_src}" "${home}/.config"
  chown -R "${user}:${user}" "${home}/.config"
}

# ── Desktop-specific dotfile deployment ──────────────────────────────
# Deploy dotfiles from dotfiles/<desktop>/ to the user's ~/.config/.
# Usage: deploy_desktop_dotfiles <desktop-name>
deploy_desktop_dotfiles() {
  local desktop="${1:?deploy_desktop_dotfiles requires desktop name}"
  local user="${LOGOS_USERNAME:?LOGOS_USERNAME not set}"
  local home="/home/${user}"
  local desktop_src

  if [[ -d "/root/LogOS/dotfiles/${desktop}" ]]; then
    desktop_src="/root/LogOS/dotfiles/${desktop}"
  elif [[ -d "${LOGOS_ROOT}/dotfiles/${desktop}" ]]; then
    desktop_src="${LOGOS_ROOT}/dotfiles/${desktop}"
  else
    log_warn "No dotfiles for ${desktop} — skipping"
    return 0
  fi

  log "Deploying ${desktop} dotfiles to ${home}/.config/"
  deploy_dotfiles "${desktop_src}" "${home}/.config"
  chown -R "${user}:${user}" "${home}/.config"
}

# ── Shared packages ──────────────────────────────────────────────────
# Install packages common to all desktop environments.
install_shared_packages() {
  log "Installing Pipewire audio stack"
  install_pkgs pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber

  log "Installing fonts"
  install_pkgs \
    noto-fonts noto-fonts-cjk noto-fonts-emoji \
    ttf-liberation ttf-dejavu \
    ttf-fira-code ttf-jetbrains-mono

  log "Installing XDG utilities"
  install_pkgs xdg-user-dirs xdg-utils
}

# ── GPU driver installation ──────────────────────────────────────────
install_gpu_drivers() {
  log "Detecting GPU(s)"
  mapfile -t gpus < <(detect_gpu)

  for gpu in "${gpus[@]}"; do
    case "${gpu}" in
      nvidia)
        log "Installing NVIDIA drivers"
        install_pkgs nvidia nvidia-utils nvidia-settings nvidia-lts
        ;;
      amd)
        log "Installing AMD GPU drivers"
        install_pkgs mesa vulkan-radeon libva-mesa-driver
        ;;
      intel)
        log "Installing Intel GPU drivers"
        install_pkgs mesa vulkan-intel intel-media-driver
        ;;
      none)
        log_warn "No discrete GPU detected — using framebuffer"
        ;;
    esac
  done
}

# ── Login manager helpers ────────────────────────────────────────────
# Configure greetd + tuigreet for Wayland compositors.
# Usage: configure_greetd <session-command>
configure_greetd() {
  local session_cmd="${1:?configure_greetd requires a session command}"

  install_pkgs greetd greetd-tuigreet

  mkdir -p /etc/greetd

  cat > /etc/greetd/config.toml <<GREETDEOF
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --cmd ${session_cmd}"
user = "greeter"
GREETDEOF

  rc-update add greetd default
  log_ok "greetd configured — session: ${session_cmd}"
}

# Configure SDDM for KDE Plasma.
configure_sddm() {
  install_pkgs sddm
  rc-update add sddm default
  log_ok "SDDM enabled"
}

# Configure LightDM for i3/X11.
configure_lightdm() {
  install_pkgs lightdm lightdm-gtk-greeter
  rc-update add lightdm default
  log_ok "LightDM enabled"
}

# ── Resolve terminal emulator ───────────────────────────────────────
# Returns the terminal package to install based on config or desktop default.
resolve_terminal() {
  local desktop="${1:?resolve_terminal requires desktop name}"
  local terminal="${LOGOS_TERMINAL:-}"

  if [[ -z "${terminal}" ]]; then
    case "${desktop}" in
      hyprland|kde) terminal="kitty" ;;
      sway|i3)     terminal="alacritty" ;;
    esac
  fi

  echo "${terminal}"
}
