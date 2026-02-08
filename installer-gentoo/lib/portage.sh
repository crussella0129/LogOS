#!/usr/bin/env bash
# LogOS Gentoo — Portage helpers
# emerge wrapper, overlay management

[[ -n "${_LOGOS_PORTAGE_LOADED:-}" ]] && return 0
readonly _LOGOS_PORTAGE_LOADED=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# Install packages via emerge (--noreplace = skip if already installed)
emerge_pkgs() {
  if [[ $# -eq 0 ]]; then
    warn "emerge_pkgs called with no arguments"
    return 0
  fi
  log "Emerging: $*"
  emerge --noreplace --quiet "$@"
}

# Install packages via emerge with --newuse (respect USE flag changes)
emerge_pkgs_update() {
  if [[ $# -eq 0 ]]; then
    warn "emerge_pkgs_update called with no arguments"
    return 0
  fi
  log "Emerging (newuse): $*"
  emerge --noreplace --newuse --quiet "$@"
}

# World-update with deep dependency resolution
emerge_world_update() {
  log "Running world update"
  emerge --update --deep --newuse --quiet @world
}

# Add a Gentoo overlay (repository)
add_overlay() {
  local name="$1"
  local sync_uri="${2:-}"

  if eselect repository list -i | grep -q "${name}"; then
    log "Overlay '${name}' already enabled"
    return 0
  fi

  if [[ -n "${sync_uri}" ]]; then
    log "Adding overlay '${name}' from ${sync_uri}"
    eselect repository add "${name}" git "${sync_uri}"
  else
    log "Enabling overlay '${name}'"
    eselect repository enable "${name}"
  fi
  emaint sync -r "${name}"
}

# Install the logos-overlay from local path
install_logos_overlay() {
  local overlay_src="${SCRIPT_DIR}/overlays/logos-overlay"
  local overlay_dst="/var/db/repos/logos-overlay"

  if [[ ! -d "${overlay_src}" ]]; then
    warn "logos-overlay source not found at ${overlay_src}"
    return 1
  fi

  log "Installing logos-overlay to ${overlay_dst}"
  mkdir -p "${overlay_dst}"
  cp -a "${overlay_src}/." "${overlay_dst}/"

  # Register with repos.conf if not already
  if [[ ! -f "/etc/portage/repos.conf/logos-overlay.conf" ]]; then
    mkdir -p /etc/portage/repos.conf
    cat > /etc/portage/repos.conf/logos-overlay.conf << REPOEOF
[logos-overlay]
location = ${overlay_dst}
auto-sync = no
REPOEOF
  fi
}

# Ensure eselect-repository is available
ensure_eselect_repository() {
  if ! command -v eselect >/dev/null 2>&1; then
    die "eselect not found — is this a Gentoo system?"
  fi
  emerge_pkgs app-eselect/eselect-repository
}
