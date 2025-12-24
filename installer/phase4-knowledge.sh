#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root."
  exit 1
fi

log() { echo "[phase4] $*"; }
install_pkgs() { pacman -S --noconfirm --needed "$@"; }

log "Creating Cold Canon directory structure"
mkdir -p /srv/cold-canon/{documents,software,datasets,media}
mkdir -p /srv/warm-mesh
mkdir -p /srv/hot-workspace
chown -R root:wheel /srv/cold-canon
chmod -R 750 /srv/cold-canon

if [[ "${INSTALL_OLLAMA:-0}" == "1" ]]; then
  log "Installing Ollama"
  curl -fsSL https://ollama.com/install.sh | sh
  systemctl enable ollama.service
  systemctl start ollama.service
  log "Pulling recommended models (this can take a while)"
  ollama pull llama3.1:8b
  ollama pull qwen2.5:7b
  ollama pull mistral:7b
fi

if [[ "${INSTALL_KIWIX:-0}" == "1" ]]; then
  log "Installing Kiwix"
  install_pkgs kiwix-tools kiwix-desktop
fi

if [[ -n "${TARGET_USER:-}" ]]; then
  log "Installing logos-assist for user ${TARGET_USER}"
  user_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
  if [[ -z "${user_home}" ]]; then
    echo "Unable to resolve home for TARGET_USER=${TARGET_USER}" >&2
    exit 1
  fi
  install -d -m 0755 "${user_home}/.local/bin"
  cat > "${user_home}/.local/bin/logos-assist" << 'EOF'
#!/usr/bin/env bash
MODEL="${LOGOS_MODEL:-llama3.1:8b}"

if [[ -z "${1:-}" ]]; then
  echo "LogOS Assistant (Model: ${MODEL})"
  echo "Type your query, or 'exit' to quit"
  echo "---"
  while true; do
    read -r -p ">>>>> " query
    [[ "${query}" == "exit" ]] && break
    ollama run "${MODEL}" "${query}"
    echo ""
  done
else
  ollama run "${MODEL}" "$*"
fi
EOF
  chown "${TARGET_USER}":"${TARGET_USER}" "${user_home}/.local/bin/logos-assist"
  chmod 0755 "${user_home}/.local/bin/logos-assist"
else
  log "TARGET_USER not set; skipping logos-assist install"
fi

log "Phase 4 complete."
