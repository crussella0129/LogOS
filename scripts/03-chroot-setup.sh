#!/usr/bin/env bash
# 03-chroot-setup.sh — System Identity + Initramfs
# Context: Run inside artix-chroot /mnt, after 02-base-install.sh.
# Configures timezone, locale, hostname, user, and mkinitcpio.
# Uses OpenRC for service management — no systemd.

LOGOS_SECTION="03-chroot"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Inside chroot, config is at /root/LogOS/
if [[ -f /root/LogOS/lib/common.sh ]]; then
  source /root/LogOS/lib/common.sh
  load_config /root/LogOS/logos.conf
else
  source "${SCRIPT_DIR}/../lib/common.sh"
  load_config "${SCRIPT_DIR}/../logos.conf"
fi

require_root
require_chroot

# ── Timezone ────────────────────────────────────────────────────────
log "Setting timezone to ${LOGOS_TIMEZONE}"
ln -sf "/usr/share/zoneinfo/${LOGOS_TIMEZONE}" /etc/localtime
hwclock --systohc
log_ok "Timezone set"

# ── Locale ──────────────────────────────────────────────────────────
log "Configuring locale: ${LOGOS_LOCALE:-en_US.UTF-8}"
LOCALE="${LOGOS_LOCALE:-en_US.UTF-8}"
sed -i "s/^#${LOCALE}/${LOCALE}/" /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
log_ok "Locale configured"

# ── Keymap ──────────────────────────────────────────────────────────
log "Setting console keymap: ${LOGOS_KEYMAP:-us}"
echo "KEYMAP=${LOGOS_KEYMAP:-us}" > /etc/vconsole.conf
log_ok "Keymap set"

# ── Hostname + hosts ───────────────────────────────────────────────
log "Setting hostname: ${LOGOS_HOSTNAME}"
echo "${LOGOS_HOSTNAME}" > /etc/hostname

cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${LOGOS_HOSTNAME}.localdomain ${LOGOS_HOSTNAME}
EOF
log_ok "Hostname and hosts configured"

# ── Root password ──────────────────────────────────────────────────
log "Set the root password (emergency use only):"
passwd

# ── User creation ──────────────────────────────────────────────────
log "Creating user: ${LOGOS_USERNAME}"
if id "${LOGOS_USERNAME}" >/dev/null 2>&1; then
  log_warn "User ${LOGOS_USERNAME} already exists — skipping creation"
else
  useradd -m -G wheel -s "${LOGOS_SHELL:-/bin/bash}" "${LOGOS_USERNAME}"
  log_ok "User created"
fi

log "Set password for ${LOGOS_USERNAME}:"
passwd "${LOGOS_USERNAME}"

# ── Sudo for wheel group ──────────────────────────────────────────
log "Enabling sudo for wheel group"
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel
log_ok "Sudo configured (via /etc/sudoers.d/wheel)"

# ── mkinitcpio ─────────────────────────────────────────────────────
log "Writing mkinitcpio.conf"
cat > /etc/mkinitcpio.conf << 'EOF'
# LogOS Artix mkinitcpio configuration
# encrypt MUST come before filesystems (order matters)

MODULES=(btrfs)

BINARIES=()

FILES=()

HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt btrfs filesystems fsck)

COMPRESSION="zstd"
COMPRESSION_OPTIONS=(-9 -T0)
EOF

log "Generating initramfs for all kernels"
mkinitcpio -P
log_ok "Initramfs generated"

# ── Enable core services (OpenRC) ─────────────────────────────────
log "Enabling core services via OpenRC"
rc-update add NetworkManager default
rc-update add elogind boot

# AppArmor and audit — add if their init scripts exist
if [[ -f /etc/init.d/apparmor ]]; then
  rc-update add apparmor boot
  log_ok "AppArmor enabled (boot runlevel)"
else
  log_warn "AppArmor init script not found — may need manual setup"
fi

if [[ -f /etc/init.d/auditd ]]; then
  rc-update add auditd default
  log_ok "Audit daemon enabled"
else
  log_warn "auditd init script not found — may need manual setup"
fi

log_ok "Core services enabled via OpenRC"

log_ok "Chroot setup complete. Proceed to 04-bootloader.sh"
