#!/usr/bin/env bash
# LogOS Gentoo — common library
# Logging, error handling, root check

set -euo pipefail

readonly LOGOS_VERSION="2026.1"
readonly LOGOS_CODENAME="Ringed City"

# Colors (only if terminal supports them)
if [[ -t 1 ]]; then
  readonly RED=$'\e[31m' GREEN=$'\e[32m' YELLOW=$'\e[33m'
  readonly BLUE=$'\e[34m' BOLD=$'\e[1m' RESET=$'\e[0m'
else
  readonly RED="" GREEN="" YELLOW="" BLUE="" BOLD="" RESET=""
fi

log()   { echo "${GREEN}[LogOS]${RESET} $*"; }
warn()  { echo "${YELLOW}[WARN]${RESET} $*" >&2; }
error() { echo "${RED}[ERROR]${RESET} $*" >&2; }
die()   { error "$*"; exit 1; }

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "This script must be run as root."
}

# Confirm a destructive action
confirm() {
  local prompt="${1:-Continue?}"
  read -r -p "${BOLD}${prompt} [y/N]${RESET} " response
  [[ "${response}" =~ ^[Yy]$ ]]
}

# Check that required commands are available
require_cmds() {
  local cmd
  for cmd in "$@"; do
    command -v "${cmd}" >/dev/null 2>&1 || die "Required command not found: ${cmd}"
  done
}

# Run a command, logging it first
run() {
  log "Running: $*"
  "$@"
}

# Source guard — prevent double-sourcing
[[ -n "${_LOGOS_COMMON_LOADED:-}" ]] && return 0
readonly _LOGOS_COMMON_LOADED=1
