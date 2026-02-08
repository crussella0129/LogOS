#!/usr/bin/env bash
# LogOS Gentoo — Phase 2: Security Transform
# Kernels, GRUB Ringed City profiles, security hardening
#
# Run inside chroot (or on booted system)
# Prerequisites: Phase 1 completed
#
# Usage: ./phase2-transform.sh
#   ENV: ENABLE_HARDENED=1  — install hardened-sources (optional)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/portage.sh"
source "${SCRIPT_DIR}/lib/uuid.sh"

require_root

# ── Detect UUIDs ──────────────────────────────────────────────────
if [[ -f /tmp/logos-uuids ]]; then
  load_uuids /tmp/logos-uuids
else
  detect_crypt_uuid
  detect_btrfs_uuid
fi

# ── Kernel Installation ──────────────────────────────────────────
log "Installing distribution kernel (Gael fallback)"
emerge_pkgs sys-kernel/gentoo-kernel sys-kernel/linux-firmware

log "Installing zen-sources for compilation (Midir/Halflight)"
emerge_pkgs sys-kernel/zen-sources

# Build zen kernel
ZEN_SRC="$(ls -d /usr/src/linux-*zen* 2>/dev/null | sort -V | tail -1)"
if [[ -n "${ZEN_SRC}" ]]; then
  log "Compiling zen kernel from ${ZEN_SRC}"
  cd "${ZEN_SRC}"

  # Use existing config or generate default
  if [[ ! -f .config ]]; then
    make defconfig
  fi

  # Enable critical options for LogOS
  scripts/config --enable CONFIG_BLK_DEV_DM
  scripts/config --enable CONFIG_DM_CRYPT
  scripts/config --enable CONFIG_BTRFS_FS
  scripts/config --enable CONFIG_BTRFS_FS_POSIX_ACL
  scripts/config --enable CONFIG_CRYPTO_AES
  scripts/config --enable CONFIG_CRYPTO_XTS
  scripts/config --enable CONFIG_CRYPTO_SHA512
  scripts/config --enable CONFIG_SECURITY_APPARMOR
  scripts/config --enable CONFIG_AUDIT

  make olddefconfig || die "Kernel config failed"
  make -j"$(nproc)" || die "Kernel build failed"
  make modules_install || die "Kernel module installation failed"
  make install || die "Kernel install failed"

  cd "${SCRIPT_DIR}"
else
  warn "zen-sources directory not found — skipping compilation"
fi

# Optional: hardened kernel
if [[ "${ENABLE_HARDENED:-0}" == "1" ]]; then
  log "Installing hardened-sources"
  emerge_pkgs sys-kernel/hardened-sources

  HARDENED_SRC="$(ls -d /usr/src/linux-*hardened* 2>/dev/null | sort -V | tail -1)"
  if [[ -n "${HARDENED_SRC}" ]]; then
    log "Compiling hardened kernel from ${HARDENED_SRC}"
    cd "${HARDENED_SRC}"
    [[ -f .config ]] || make defconfig
    scripts/config --enable CONFIG_BLK_DEV_DM
    scripts/config --enable CONFIG_DM_CRYPT
    scripts/config --enable CONFIG_BTRFS_FS
    scripts/config --enable CONFIG_BTRFS_FS_POSIX_ACL
    scripts/config --enable CONFIG_SECURITY_APPARMOR
    scripts/config --enable CONFIG_AUDIT
    make olddefconfig || die "Hardened kernel config failed"
    make -j"$(nproc)" || die "Hardened kernel build failed"
    make modules_install || die "Hardened kernel module installation failed"
    make install || die "Hardened kernel install failed"
    cd "${SCRIPT_DIR}"
  fi
fi

# Verify at least one kernel was installed
if ! ls /boot/vmlinuz-* &>/dev/null; then
  die "No kernel found in /boot — kernel installation failed"
fi
log "Kernel verification: $(ls /boot/vmlinuz-* 2>/dev/null | wc -l) kernel(s) installed"

# ── Initramfs (dracut) ───────────────────────────────────────────
log "Configuring dracut"
mkdir -p /etc/dracut.conf.d
cp "${SCRIPT_DIR}/configs/dracut.conf" /etc/dracut.conf.d/logos.conf

log "Generating initramfs for all installed kernels"
for kernel_dir in /lib/modules/*/; do
  kver="$(basename "${kernel_dir}")"
  if [[ -f "/boot/vmlinuz-${kver}" ]] || [[ -f "/boot/vmlinuz-${kver%-*}" ]]; then
    log "  Building initramfs for ${kver}"
    dracut --force "/boot/initramfs-${kver}.img" "${kver}"
  fi
done

# ── CPU microcode ─────────────────────────────────────────────────
log "Installing CPU microcode"
if grep -q "GenuineIntel" /proc/cpuinfo 2>/dev/null; then
  emerge_pkgs sys-firmware/intel-microcode
elif grep -q "AuthenticAMD" /proc/cpuinfo 2>/dev/null; then
  log "AMD microcode included in linux-firmware"
fi

# ── Security packages ────────────────────────────────────────────
log "Installing security services"
emerge_pkgs sys-apps/apparmor sys-apps/apparmor-utils \
            sys-process/audit \
            net-firewall/ufw \
            net-analyzer/fail2ban \
            net-misc/openssh

for svc in apparmor auditd ufw fail2ban sshd; do
  if systemctl enable "${svc}.service" 2>/dev/null; then
    log "  Enabled: ${svc}"
  else
    warn "Failed to enable ${svc} — package may not be installed"
  fi
done

# ── Firewall defaults ────────────────────────────────────────────
log "Configuring firewall"
ufw default deny incoming || warn "Failed to set default deny policy"
ufw default allow outgoing || warn "Failed to set default allow policy"
ufw --force enable || warn "Failed to enable firewall"

# ── Sysctl hardening ─────────────────────────────────────────────
log "Applying sysctl hardening"
cp "${SCRIPT_DIR}/security/99-logos-hardening.conf" /etc/sysctl.d/

# ── Audit rules ──────────────────────────────────────────────────
log "Installing audit rules"
mkdir -p /etc/audit/rules.d
cp "${SCRIPT_DIR}/security/logos-audit.rules" /etc/audit/rules.d/

# ── SSH hardening ─────────────────────────────────────────────────
log "Applying SSH hardening"
mkdir -p /etc/ssh/sshd_config.d
cp "${SCRIPT_DIR}/security/10-logos-ssh.conf" /etc/ssh/sshd_config.d/

# ── GRUB configuration ───────────────────────────────────────────
log "Installing GRUB"
emerge_pkgs sys-boot/grub

log "Writing GRUB defaults"
cp "${SCRIPT_DIR}/grub/grub-defaults" /etc/default/grub

# Inject LUKS UUID into GRUB defaults
if [[ -n "${CRYPT_UUID:-}" ]]; then
  sed -i "s|@CRYPT_UUID@|${CRYPT_UUID}|g" /etc/default/grub
fi

log "Installing GRUB to EFI"
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=LogOS

log "Installing Ringed City GRUB profiles"
cp "${SCRIPT_DIR}/grub/41_logos_profiles" /etc/grub.d/41_logos_profiles
chmod +x /etc/grub.d/41_logos_profiles

# Disable default kernel entries (we use our own profiles)
chmod -x /etc/grub.d/10_linux 2>/dev/null || true

log "Generating GRUB configuration"
grub-mkconfig -o /boot/grub/grub.cfg

# ── Core utilities ────────────────────────────────────────────────
log "Installing core utilities"
emerge_pkgs sys-fs/btrfs-progs app-backup/snapper \
            sys-process/htop sys-process/btop \
            app-misc/neofetch app-misc/fastfetch \
            app-text/tree net-misc/wget net-misc/curl \
            net-misc/rsync net-misc/openssh \
            app-misc/tmux app-shells/zsh \
            sys-apps/man-pages

# ── Rust CLI tools ────────────────────────────────────────────────
log "Installing Rust CLI tooling"
emerge_pkgs sys-apps/ripgrep sys-apps/fd sys-apps/bat \
            app-misc/eza sys-process/bottom \
            app-shells/starship dev-util/tokei \
            sys-apps/dust app-shells/zoxide \
            sys-process/procs || warn "Some Rust tools may not be in tree — will try overlay later"

# ── Snapper configuration ────────────────────────────────────────
log "Configuring Snapper"
if command -v snapper >/dev/null 2>&1; then
  if [[ ! -f /etc/snapper/configs/root ]]; then
    snapper -c root create-config / 2>/dev/null || warn "Snapper config creation failed — configure manually"
  fi
fi

# ── Install kernel watchdog service ──────────────────────────────
log "Installing kernel watchdog service"
cp "${SCRIPT_DIR}/services/logos-kernel-watchdog.service" /etc/systemd/system/
cp "${SCRIPT_DIR}/services/logos-kernel-watchdog.timer"   /etc/systemd/system/
mkdir -p /usr/local/lib/logos
cp "${SCRIPT_DIR}/kernel/kernel-watchdog.sh" /usr/local/lib/logos/
chmod +x /usr/local/lib/logos/kernel-watchdog.sh
systemctl enable logos-kernel-watchdog.timer

# ── Install validation tool ──────────────────────────────────────
install -Dm755 "${SCRIPT_DIR}/tools/logos-validate-boot" /usr/local/bin/logos-validate-boot

# ── Branding ──────────────────────────────────────────────────────
log "Writing LogOS branding"
cat > /etc/logos-release << 'EOF'
NAME="LogOS"
VERSION="2026.1"
CODENAME="Ringed City"
BASE="Gentoo Linux"
ARCHITECTURE="x86_64"
INSTALLATION_METHOD="phase-scripts"
EOF

cat > /etc/motd << 'EOF'
LogOS Gentoo — Ringed City Build
Profiles: Gael (Security) | Midir (Balanced) | Halflight (Performance)
"Knowledge preserved. Reason applied. Civilization continued."
EOF

systemctl enable NetworkManager.service

log "Phase 2 complete. Reboot when ready."
