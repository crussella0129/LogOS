#!/usr/bin/env bash
# LogOS Gentoo — Phase 4: Knowledge Infrastructure
# Ollama (local LLM), Kiwix (offline docs), Cold Canon structure
#
# Run on booted system as root.
# Prerequisites: Phase 3 completed (or at least Phase 2)
#
# Usage: INSTALL_OLLAMA=1 INSTALL_KIWIX=1 TARGET_USER=charles ./phase4-knowledge.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/portage.sh"

require_root

# ── Cold Canon Directory Structure ────────────────────────────────
log "Creating Cold Canon directory structure"
mkdir -p /srv/cold-canon/{documents,software,datasets,media}
mkdir -p /srv/warm-mesh
mkdir -p /srv/hot-workspace
chown -R root:wheel /srv/cold-canon
chmod -R 750 /srv/cold-canon
chown -R root:wheel /srv/warm-mesh /srv/hot-workspace
chmod -R 770 /srv/warm-mesh /srv/hot-workspace

# ── Ollama (Local LLM) ───────────────────────────────────────────
if [[ "${INSTALL_OLLAMA:-0}" == "1" ]]; then
  log "Installing Ollama"
  # Ollama provides its own installer (distro-agnostic)
  curl -fsSL https://ollama.com/install.sh | sh

  systemctl enable ollama.service
  systemctl start ollama.service

  log "Pulling recommended models (this can take a while)"
  ollama pull llama3.1:8b
  ollama pull qwen2.5:7b
  ollama pull mistral:7b
fi

# ── Kiwix (Offline Documentation) ────────────────────────────────
if [[ "${INSTALL_KIWIX:-0}" == "1" ]]; then
  log "Installing Kiwix"
  emerge_pkgs app-misc/kiwix-tools 2>/dev/null || {
    warn "kiwix-tools not in tree — installing from logos-overlay"
    install_logos_overlay 2>/dev/null || warn "logos-overlay not available"
    emerge_pkgs app-misc/kiwix-tools 2>/dev/null || warn "Kiwix install failed — create ebuild"
  }
fi

# ── logos-assist CLI Tool ─────────────────────────────────────────
if [[ -n "${TARGET_USER:-}" ]]; then
  log "Installing logos-assist for user ${TARGET_USER}"
  user_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
  if [[ -z "${user_home}" ]]; then
    die "Unable to resolve home for TARGET_USER=${TARGET_USER}"
  fi

  install -d -m 0755 "${user_home}/.local/bin"
  install -m 0755 "${SCRIPT_DIR}/tools/logos-assist" "${user_home}/.local/bin/logos-assist"
  chown "${TARGET_USER}":"${TARGET_USER}" "${user_home}/.local/bin/logos-assist"

  # Also install logos-canon-promote
  install -m 0755 "${SCRIPT_DIR}/tools/logos-canon-promote" "${user_home}/.local/bin/logos-canon-promote"
  chown "${TARGET_USER}":"${TARGET_USER}" "${user_home}/.local/bin/logos-canon-promote"

  log "Tools installed to ${user_home}/.local/bin/"
else
  log "TARGET_USER not set; skipping user tool installation"
  log "System-wide install:"
  install -m 0755 "${SCRIPT_DIR}/tools/logos-assist" /usr/local/bin/logos-assist
  install -m 0755 "${SCRIPT_DIR}/tools/logos-canon-promote" /usr/local/bin/logos-canon-promote
fi

log "Phase 4 complete."
