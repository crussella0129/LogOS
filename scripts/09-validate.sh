#!/usr/bin/env bash
# 09-validate.sh — Post-Build Validation
# Context: Run on the booted system. Read-only — never modifies the system.
# Runs pass/fail/warn checks across boot, encryption, filesystem, security,
# kernel hardening, network, snapshots, and knowledge categories.
#
# Ported from: Master spec section 25 (validation suite)

LOGOS_SECTION="09-validate"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f /root/LogOS/lib/common.sh ]]; then
  source /root/LogOS/lib/common.sh
else
  source "${SCRIPT_DIR}/../lib/common.sh"
fi

# Override the ERR trap — we don't want validation checks to abort the script
trap - ERR
set +e

require_root

PASS=0
FAIL=0
WARN=0

pass() { printf '\033[0;32m  ✓ %s\033[0m\n' "$1"; ((PASS++)); }
fail() { printf '\033[0;31m  ✗ %s\033[0m\n' "$1"; ((FAIL++)); }
warn() { printf '\033[0;33m  ⚠ %s\033[0m\n' "$1"; ((WARN++)); }

section() {
  echo ""
  echo "━━━ $1 ━━━"
}

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║           LogOS System Validation Suite                    ║"
echo "╚════════════════════════════════════════════════════════════╝"

# ── Boot Configuration ─────────────────────────────────────────────
section "Boot Configuration"

[[ -d /sys/firmware/efi ]]                     && pass "UEFI boot mode"             || fail "Not UEFI boot"
[[ -f /boot/efi/EFI/LogOS/grubx64.efi ]]      && pass "GRUB bootloader installed"   || fail "GRUB not found"
[[ -f /boot/vmlinuz-linux ]]                   && pass "Standard kernel present"     || fail "Standard kernel missing"
[[ -f /boot/vmlinuz-linux-lts ]]               && pass "LTS kernel present"          || fail "LTS kernel missing"
[[ -f /boot/vmlinuz-linux-zen ]]               && pass "Zen kernel present"          || fail "Zen kernel missing"
[[ -f /boot/vmlinuz-linux-hardened ]]          && pass "Hardened kernel present"     || warn "Hardened kernel not installed (optional)"

# ── Encryption ─────────────────────────────────────────────────────
section "Encryption"

[[ -e /dev/mapper/cryptroot ]]                 && pass "LUKS volume active"          || fail "LUKS not active"
grep -q "cryptdevice=" /proc/cmdline 2>/dev/null && pass "cryptdevice in cmdline"    || fail "cryptdevice not in cmdline"

# ── Filesystem ─────────────────────────────────────────────────────
section "Filesystem"

mount | grep -q "subvol=/@,"                   && pass "Root subvolume mounted"      || fail "Root subvolume not mounted"
mount | grep -q "subvol=/@home"                && pass "Home subvolume mounted"      || fail "Home subvolume not mounted"
mount | grep -q "subvol=/@snapshots"           && pass "Snapshots subvolume mounted" || fail "Snapshots not mounted"
mount | grep -q "subvol=/@log"                 && pass "Log subvolume mounted"       || warn "Log subvolume not mounted"
mount | grep -q "subvol=/@pkg"                 && pass "Package cache subvol mounted"|| warn "Package cache subvol not mounted"
mount | grep -q "subvol=/@canon"               && pass "Cold Canon subvol mounted"   || warn "Cold Canon subvol not mounted"
# Note: copies=2 is a btrfs filesystem property, not visible in mount output.
# Check the @canon subvol exists and is mounted instead.
[[ -d /srv/cold-canon/documents ]]             && pass "Cold Canon structure intact"  || warn "Cold Canon subdirs not found"
mount | grep -q "compress=zstd"                && pass "Compression enabled"         || warn "Compression not detected"

# Btrfs health
errors=$(btrfs device stats / 2>/dev/null | grep -v ' 0$' | wc -l)
[[ "${errors}" -eq 0 ]]                        && pass "No Btrfs errors"             || fail "${errors} Btrfs error counters non-zero"

# ── Security Services ─────────────────────────────────────────────
section "Security Services"

systemctl is-active --quiet apparmor            && pass "AppArmor running"           || fail "AppArmor not running"
systemctl is-active --quiet auditd              && pass "Audit daemon running"       || fail "Audit not running"
systemctl is-active --quiet ufw                 && pass "UFW running"                || fail "UFW not running"
systemctl is-active --quiet fail2ban 2>/dev/null && pass "fail2ban running"          || warn "fail2ban not running"

aa-status 2>/dev/null | grep -q "apparmor module is loaded" \
  && pass "AppArmor module loaded"              || fail "AppArmor module not loaded"

grep -q "apparmor=1" /proc/cmdline 2>/dev/null  && pass "apparmor=1 in cmdline"     || fail "apparmor not in cmdline"
grep -q "audit=1" /proc/cmdline 2>/dev/null     && pass "audit=1 in cmdline"        || warn "audit not in cmdline (Halflight?)"

# ── Kernel Hardening ──────────────────────────────────────────────
section "Kernel Hardening"

[[ "$(cat /proc/sys/kernel/randomize_va_space 2>/dev/null)" == "2" ]] \
  && pass "ASLR enabled (full)"                 || fail "ASLR not fully enabled"
[[ "$(cat /proc/sys/kernel/dmesg_restrict 2>/dev/null)" == "1" ]] \
  && pass "dmesg restricted"                    || warn "dmesg not restricted"
[[ "$(cat /proc/sys/kernel/kptr_restrict 2>/dev/null)" == "2" ]] \
  && pass "kptr restricted"                     || warn "kptr not restricted"
[[ "$(cat /proc/sys/kernel/perf_event_paranoid 2>/dev/null)" == "3" ]] \
  && pass "perf_event_paranoid=3"               || warn "perf not maximally restricted"
[[ "$(cat /proc/sys/net/ipv4/tcp_syncookies 2>/dev/null)" == "1" ]] \
  && pass "TCP syncookies enabled"              || warn "TCP syncookies not enabled"

# ── Network ────────────────────────────────────────────────────────
section "Network"

systemctl is-active --quiet NetworkManager      && pass "NetworkManager running"     || fail "NetworkManager not running"
ufw status 2>/dev/null | grep -q "Status: active" \
  && pass "UFW firewall active"                 || fail "UFW not active"

# ── SSH (if enabled) ──────────────────────────────────────────────
if systemctl is-enabled --quiet sshd 2>/dev/null; then
  section "SSH Hardening"
  [[ -f /etc/ssh/sshd_config.d/10-logos.conf ]]  && pass "SSH hardening config present" || warn "SSH hardening config missing"
  grep -q "PermitRootLogin no" /etc/ssh/sshd_config.d/10-logos.conf 2>/dev/null \
    && pass "Root login disabled"               || warn "Root login not explicitly disabled"
  grep -q "PasswordAuthentication no" /etc/ssh/sshd_config.d/10-logos.conf 2>/dev/null \
    && pass "Password auth disabled"            || warn "Password auth not disabled"
fi

# ── Snapshots ──────────────────────────────────────────────────────
section "Snapshots"

systemctl is-active --quiet snapper-timeline.timer 2>/dev/null \
  && pass "Snapper timeline active"             || warn "Snapper timeline not active"
systemctl is-active --quiet snapper-cleanup.timer 2>/dev/null \
  && pass "Snapper cleanup active"              || warn "Snapper cleanup not active"
snapper -c root list >/dev/null 2>&1            && pass "Snapper root config exists" || warn "Snapper not configured"

# ── Desktop Environment ──────────────────────────────────────────
section "Desktop Environment"

# Load config to check LOGOS_DESKTOP
if [[ -f /root/LogOS/logos.conf ]]; then
  # shellcheck source=/dev/null
  source /root/LogOS/logos.conf 2>/dev/null
fi
_desktop="${LOGOS_DESKTOP:-hyprland}"

case "${_desktop}" in
  hyprland)
    command -v Hyprland >/dev/null 2>&1      && pass "Hyprland installed"         || fail "Hyprland not found"
    command -v waybar >/dev/null 2>&1         && pass "Waybar installed"           || fail "Waybar not found"
    systemctl is-enabled --quiet greetd 2>/dev/null \
      && pass "greetd enabled"               || fail "greetd not enabled"
    [[ -f /etc/greetd/config.toml ]]         && pass "greetd config present"      || fail "greetd config missing"
    ;;
  kde)
    command -v plasmashell >/dev/null 2>&1    && pass "KDE Plasma installed"       || fail "KDE Plasma not found"
    systemctl is-enabled --quiet sddm 2>/dev/null \
      && pass "SDDM enabled"                || fail "SDDM not enabled"
    ;;
  sway)
    command -v sway >/dev/null 2>&1           && pass "Sway installed"             || fail "Sway not found"
    command -v waybar >/dev/null 2>&1         && pass "Waybar installed"           || fail "Waybar not found"
    systemctl is-enabled --quiet greetd 2>/dev/null \
      && pass "greetd enabled"               || fail "greetd not enabled"
    ;;
  i3)
    command -v i3 >/dev/null 2>&1             && pass "i3 installed"               || fail "i3 not found"
    systemctl is-enabled --quiet lightdm 2>/dev/null \
      && pass "LightDM enabled"              || fail "LightDM not enabled"
    ;;
esac

# Common desktop checks
command -v pipewire >/dev/null 2>&1          && pass "Pipewire installed"         || fail "Pipewire not found"
[[ -d "/home/${LOGOS_USERNAME:-logos}/.config" ]] \
  && pass "User .config directory exists"    || warn "User .config not found"

# Theme verification: check no unreplaced placeholders in deployed configs
_config_dir="/home/${LOGOS_USERNAME:-logos}/.config"
if [[ -d "${_config_dir}" ]]; then
  _stale=$(grep -rl '@@THEME_' "${_config_dir}" 2>/dev/null | head -5)
  if [[ -z "${_stale}" ]]; then
    pass "No unreplaced theme placeholders"
  else
    fail "Unreplaced @@THEME_*@@ in: ${_stale}"
  fi
fi

# ── Knowledge Infrastructure ──────────────────────────────────────
section "Knowledge Infrastructure"

[[ -d /srv/cold-canon ]]                        && pass "Cold Canon directory exists" || warn "Cold Canon not found"
[[ -d /srv/warm-mesh ]]                         && pass "Warm Mesh directory exists"  || warn "Warm Mesh not found"
[[ -d /srv/hot-workspace ]]                     && pass "Hot Workspace directory exists" || warn "Hot Workspace not found"
systemctl is-active --quiet ollama 2>/dev/null  && pass "Ollama service running"     || warn "Ollama not running"
[[ -f /etc/logos-release ]]                     && pass "LogOS branding present"     || warn "LogOS branding missing"

# ── Summary ────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════"
printf "Results: \033[0;32m%d passed\033[0m, \033[0;31m%d failed\033[0m, \033[0;33m%d warnings\033[0m\n" "${PASS}" "${FAIL}" "${WARN}"
echo ""

if [[ "${FAIL}" -eq 0 ]]; then
  if [[ "${WARN}" -eq 0 ]]; then
    echo "✓ System validation PASSED — all checks successful"
  else
    echo "⚠ System validation PASSED with warnings"
  fi
  exit 0
else
  echo "✗ System validation FAILED — review issues above"
  exit 1
fi
