#!/usr/bin/env bash
# LogOS Gentoo — Kernel Boot Watchdog
# Graceful degradation: Midir/zen → Gael/stable|hardened
#
# Runs 90s after boot via systemd timer.
# Checks boot health and manages GRUB saved_entry for failover.
#
# Design constraints (non-exploitability):
#   - Fallback always goes toward MORE secure (Gael), never toward Halflight
#   - Boot counter stored on LUKS-encrypted filesystem
#   - Only writes whitelisted saved_entry values
#   - All degradation events are audit-logged
#   - No kexec (unreliable in panic, potential attack vector)

set -euo pipefail

readonly STATE_DIR="/var/lib/logos-watchdog"
readonly COUNTER_FILE="${STATE_DIR}/boot-fail-counter"
readonly MAX_FAILURES=2
readonly LOG_TAG="logos-watchdog"

# Whitelisted GRUB entries — ONLY these can be set as saved_entry
readonly -a ALLOWED_ENTRIES=("logos-gael" "logos-midir" "logos-halflight")

log()  { logger -t "${LOG_TAG}" "$*"; echo "[watchdog] $*"; }
audit_log() { logger -t "${LOG_TAG}" -p auth.warning "DEGRADATION: $*"; }

mkdir -p "${STATE_DIR}"

# ── Read current boot counter ─────────────────────────────────────
read_counter() {
  if [[ -f "${COUNTER_FILE}" ]]; then
    cat "${COUNTER_FILE}"
  else
    echo "0"
  fi
}

write_counter() {
  echo "$1" > "${COUNTER_FILE}"
  chmod 600 "${COUNTER_FILE}"
}

# ── Validate GRUB entry name ─────────────────────────────────────
is_allowed_entry() {
  local entry="$1"
  local allowed
  for allowed in "${ALLOWED_ENTRIES[@]}"; do
    if [[ "${entry}" == "${allowed}" ]]; then
      return 0
    fi
  done
  return 1
}

set_grub_default() {
  local entry="$1"
  if ! is_allowed_entry "${entry}"; then
    log "REJECTED: attempt to set non-whitelisted entry '${entry}'"
    return 1
  fi
  grub-set-default "${entry}"
  log "GRUB default set to: ${entry}"
}

# ── Health checks ─────────────────────────────────────────────────
check_service() {
  systemctl is-active --quiet "$1" 2>/dev/null
}

check_health() {
  local failures=0
  local checks_run=0

  # AppArmor must be active
  if check_service apparmor.service; then
    log "  OK: apparmor active"
  else
    log "  FAIL: apparmor not active"
    ((failures++))
  fi
  ((checks_run++))

  # Audit daemon must be active
  if check_service auditd.service; then
    log "  OK: auditd active"
  else
    log "  FAIL: auditd not active"
    ((failures++))
  fi
  ((checks_run++))

  # Firewall must be active
  if check_service ufw.service; then
    log "  OK: ufw active"
  else
    log "  FAIL: ufw not active"
    ((failures++))
  fi
  ((checks_run++))

  # NetworkManager must be active
  if check_service NetworkManager.service; then
    log "  OK: NetworkManager active"
  else
    log "  FAIL: NetworkManager not active"
    ((failures++))
  fi
  ((checks_run++))

  # Kernel must not be tainted
  local taint
  taint="$(cat /proc/sys/kernel/tainted 2>/dev/null || echo "0")"
  if [[ "${taint}" == "0" ]]; then
    log "  OK: kernel not tainted"
  else
    log "  WARN: kernel tainted (${taint}) — not a boot failure"
  fi

  log "Health check: ${failures}/${checks_run} failed"
  return "${failures}"
}

# ── Main logic ────────────────────────────────────────────────────
main() {
  log "Boot watchdog starting"

  local counter
  counter="$(read_counter)"
  log "Current failure counter: ${counter}"

  # Run health checks
  local health_failures=0
  check_health || health_failures=$?

  if [[ "${health_failures}" -eq 0 ]]; then
    # Healthy boot — reset counter, confirm current kernel
    log "Boot healthy — resetting failure counter"
    write_counter 0

    # Determine current profile from kernel cmdline
    local cmdline
    cmdline="$(cat /proc/cmdline)"
    if echo "${cmdline}" | grep -q "lockdown=confidentiality"; then
      set_grub_default "logos-gael"
    elif echo "${cmdline}" | grep -q "mitigations=off"; then
      set_grub_default "logos-halflight"
    elif echo "${cmdline}" | grep -q "mitigations=auto"; then
      set_grub_default "logos-midir"
    else
      log "Could not determine current profile — keeping saved entry"
    fi
  else
    # Unhealthy boot — increment counter
    counter=$((counter + 1))
    write_counter "${counter}"

    if [[ "${counter}" -ge "${MAX_FAILURES}" ]]; then
      # Lock to Gael after repeated failures
      audit_log "Boot failure count ${counter} >= ${MAX_FAILURES} — locking to Gael"
      set_grub_default "logos-gael"
      log "LOCKED TO GAEL — manual intervention required to change profile"
    else
      audit_log "Boot failure count ${counter} — will degrade on next failure"
    fi
  fi

  log "Boot watchdog complete"
}

main "$@"
