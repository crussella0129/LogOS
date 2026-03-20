#!/usr/bin/env bash
# 08-knowledge.sh — Cold Canon + LLM + Kiwix + Branding
# Context: Run on the booted system after 07-packages.sh.
# Sets up knowledge infrastructure directories, Ollama, Kiwix,
# the logos-assist CLI helper, and LogOS branding files.
# Uses OpenRC for service management — no systemd.

LOGOS_SECTION="08-knowledge"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f /root/LogOS/lib/common.sh ]]; then
  source /root/LogOS/lib/common.sh
  load_config /root/LogOS/logos.conf
else
  source "${SCRIPT_DIR}/../lib/common.sh"
  load_config "${SCRIPT_DIR}/../logos.conf"
fi

require_root

# ── Knowledge directory structure ──────────────────────────────────
log "Creating knowledge infrastructure directories"
mkdir -p /srv/cold-canon/{documents,software,datasets,media}
mkdir -p /srv/warm-mesh
mkdir -p /srv/hot-workspace

chown -R root:wheel /srv/cold-canon
chmod -R 750 /srv/cold-canon
chown -R root:wheel /srv/warm-mesh
chmod -R 770 /srv/warm-mesh
chown -R root:wheel /srv/hot-workspace
chmod -R 770 /srv/hot-workspace

log_ok "Knowledge directories created"

# ── Ollama (local LLM) ────────────────────────────────────────────
if [[ "${LOGOS_OLLAMA:-0}" == "1" ]]; then
  log "Installing Ollama"
  # Prefer pacman (signature-verified) over curl|sh
  if pacman -Si ollama >/dev/null 2>&1; then
    install_pkgs ollama
  else
    log_warn "ollama not in repos — falling back to upstream installer"
    curl -fsSL https://ollama.com/install.sh | sh
  fi

  # Enable and start via OpenRC if init script exists, otherwise manual start
  if [[ -f /etc/init.d/ollama ]]; then
    rc-update add ollama default
    rc-service ollama start
  else
    # Ollama upstream installer may create its own service management
    ollama serve &>/dev/null &
    sleep 2
    log_warn "No OpenRC init script for ollama — started manually"
  fi

  log "Pulling LLM models (this may take a while)"
  for model in ${LOGOS_OLLAMA_MODELS:-llama3.1:8b}; do
    log "Pulling ${model}"
    ollama pull "${model}"
  done
  log_ok "Ollama installed and models pulled"
else
  log "Ollama disabled in config — skipping"
fi

# ── Kiwix (offline docs) ──────────────────────────────────────────
if [[ "${LOGOS_KIWIX:-0}" == "1" ]]; then
  log "Installing Kiwix"
  install_pkgs kiwix-tools kiwix-desktop
  log_ok "Kiwix installed"
else
  log "Kiwix disabled in config — skipping"
fi

# ── logos-assist CLI helper ────────────────────────────────────────
if [[ -n "${LOGOS_USERNAME:-}" ]]; then
  log "Installing logos-assist for ${LOGOS_USERNAME}"
  user_home="$(getent passwd "${LOGOS_USERNAME}" | cut -d: -f6)"

  if [[ -z "${user_home}" ]]; then
    log_err "Cannot resolve home directory for ${LOGOS_USERNAME}"
  else
    install -d -m 0755 "${user_home}/.local/bin"
    DEFAULT_MODEL="${LOGOS_DEFAULT_MODEL:-llama3.1:8b}"

    cat > "${user_home}/.local/bin/logos-assist" << SCRIPT
#!/usr/bin/env bash
MODEL="\${LOGOS_MODEL:-${DEFAULT_MODEL}}"

if [[ -z "\${1:-}" ]]; then
  echo "LogOS Assistant (Model: \${MODEL})"
  echo "Type your query, or 'exit' to quit"
  echo "---"
  while true; do
    read -r -p ">>>>> " query
    [[ "\${query}" == "exit" ]] && break
    ollama run "\${MODEL}" "\${query}"
    echo ""
  done
else
  ollama run "\${MODEL}" "\$*"
fi
SCRIPT

    chown "${LOGOS_USERNAME}":"${LOGOS_USERNAME}" "${user_home}/.local/bin/logos-assist"
    chmod 0755 "${user_home}/.local/bin/logos-assist"
    log_ok "logos-assist installed to ${user_home}/.local/bin/"
  fi
else
  log_warn "LOGOS_USERNAME not set — skipping logos-assist"
fi

# ── LogOS branding ─────────────────────────────────────────────────
log "Writing LogOS branding"
cat > /etc/logos-release << 'EOF'
NAME="LogOS"
VERSION="2025.8"
CODENAME="Ringed City"
BASE="Artix Linux"
INIT="OpenRC"
ARCHITECTURE="x86_64"
INSTALLATION_METHOD="literate-build"
EOF

cat > /etc/motd << 'EOF'
Ontology Substrate OS — Ringed City Build (Artix/OpenRC)
Profiles: Gael (Security) | Midir (Balanced) | Halflight (Performance)
"Knowledge preserved. Reason applied. Civilization continued."
EOF

log_ok "Knowledge infrastructure complete. Proceed to 09-validate.sh"
