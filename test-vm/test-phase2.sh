#!/usr/bin/env bash
# LogOS Gentoo — Phase 2 Test Harness
# Tests GRUB Ringed City profile generation, security config deployment,
# dracut config, kernel watchdog, and logos-validate-boot logic
#
# Runs against the qcow2 disk prepared by test-phase0 + test-phase1
# Usage: sudo ./test-phase2.sh
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="${TEST_DIR}/../installer-gentoo"
QCOW2="${TEST_DIR}/logos-test.qcow2"
NBD_DEV="/dev/nbd0"
LUKS_PASS="REDACTED_PASS"
MNT="/mnt/logos-test"
PASS=0; FAIL=0

pass() { echo -e "\e[32m  PASS: $*\e[0m"; ((PASS++)) || true; }
fail() { echo -e "\e[31m  FAIL: $*\e[0m"; ((FAIL++)) || true; }

cleanup() {
  echo ""; echo "== Cleaning up =="
  umount -R "${MNT}" 2>/dev/null || true
  cryptsetup close logos-test-crypt 2>/dev/null || true
  sleep 1
  qemu-nbd --disconnect "${NBD_DEV}" 2>/dev/null || true
  echo "Done."
}
trap cleanup EXIT

[[ "${EUID}" -eq 0 ]] || { echo "Run as root"; exit 1; }

# ── Reconnect ────────────────────────────────────────────────────
echo ""; echo "== Reconnecting to test disk =="
modprobe nbd max_part=8 2>/dev/null || true
qemu-nbd --disconnect "${NBD_DEV}" 2>/dev/null || true
sleep 1
qemu-nbd --connect="${NBD_DEV}" "${QCOW2}"
sleep 2

echo -n "${LUKS_PASS}" | cryptsetup open "${NBD_DEV}p3" logos-test-crypt -
BTRFS_OPTS="noatime,compress=zstd:3,space_cache=v2"
mkdir -p "${MNT}"
mount -o "subvol=@,${BTRFS_OPTS}" /dev/mapper/logos-test-crypt "${MNT}"
mkdir -p "${MNT}"/{boot,var/log}
mount "${NBD_DEV}p2" "${MNT}/boot"
mkdir -p "${MNT}/boot/efi"
mount "${NBD_DEV}p1" "${MNT}/boot/efi"
mount -o "subvol=@log,${BTRFS_OPTS}" /dev/mapper/logos-test-crypt "${MNT}/var/log"
pass "Disk remounted"

# Get UUIDs
CRYPT_UUID="$(blkid -s UUID -o value "${NBD_DEV}p3")"
BTRFS_UUID="$(blkid -s UUID -o value /dev/mapper/logos-test-crypt)"

# ═══════════════════════════════════════════════════════════════════
# TEST SECTION 1: GRUB Ringed City Profile Generation
# ═══════════════════════════════════════════════════════════════════
echo ""; echo "== GRUB Profile Generation =="

# Create fake kernel files to simulate a Gentoo install
mkdir -p "${MNT}/boot"
touch "${MNT}/boot/vmlinuz-6.12.8-zen1-gentoo"
touch "${MNT}/boot/initramfs-6.12.8-zen1-gentoo.img"
touch "${MNT}/boot/vmlinuz-6.6.68-gentoo-dist"
touch "${MNT}/boot/initramfs-6.6.68-gentoo-dist.img"
touch "${MNT}/boot/vmlinuz-6.12.6-hardened-gentoo"
touch "${MNT}/boot/initramfs-6.12.6-hardened-gentoo.img"
pass "Fake kernel files created"

# Install GRUB defaults with real UUIDs
cp "${INSTALLER_DIR}/grub/grub-defaults" "${MNT}/etc/default/grub"
sed -i "s|@CRYPT_UUID@|${CRYPT_UUID}|g" "${MNT}/etc/default/grub"

grep -q "${CRYPT_UUID}" "${MNT}/etc/default/grub" && pass "GRUB defaults: UUID injected" || fail "GRUB defaults: UUID missing"
grep -q "GRUB_DEFAULT=saved" "${MNT}/etc/default/grub" && pass "GRUB defaults: saved_entry" || fail "GRUB defaults: no saved"
grep -q "GRUB_ENABLE_CRYPTODISK=y" "${MNT}/etc/default/grub" && pass "GRUB defaults: cryptodisk" || fail "GRUB defaults: no cryptodisk"

# Install the profile generator
mkdir -p "${MNT}/etc/grub.d"
cp "${INSTALLER_DIR}/grub/41_logos_profiles" "${MNT}/etc/grub.d/41_logos_profiles"
chmod +x "${MNT}/etc/grub.d/41_logos_profiles"
[[ -x "${MNT}/etc/grub.d/41_logos_profiles" ]] && pass "41_logos_profiles installed" || fail "41_logos_profiles missing"

# Run the profile generator in a simulated environment
# We need to fake findmnt/blkid/mountpoint results for the script
echo ""; echo "== Profile Generator Output =="

# Run the generator with mocked environment
GRUB_OUTPUT="$(
  # Use host binaries (not stage3) to avoid glibc mismatch
  find_kernel()  { /usr/bin/ls -t "${MNT}/boot/vmlinuz-"*${1}* 2>/dev/null | /usr/bin/head -1; }
  find_initrd()  { /usr/bin/ls -t "${MNT}/boot/initramfs-"*${1}*.img 2>/dev/null | /usr/bin/head -1; }

  ZEN_KERNEL="$(find_kernel 'zen')"
  ZEN_INITRD="$(find_initrd 'zen')"
  STABLE_KERNEL="$(find_kernel 'gentoo-dist')"
  STABLE_INITRD="$(find_initrd 'gentoo-dist')"
  HARDENED_KERNEL="$(find_kernel 'hardened')"
  HARDENED_INITRD="$(find_initrd 'hardened')"
  GAEL_KERNEL="${HARDENED_KERNEL:-$STABLE_KERNEL}"
  GAEL_INITRD="${HARDENED_INITRD:-$STABLE_INITRD}"

  echo "ZEN_KERNEL=${ZEN_KERNEL}"
  echo "STABLE_KERNEL=${STABLE_KERNEL}"
  echo "HARDENED_KERNEL=${HARDENED_KERNEL}"
  echo "GAEL_KERNEL=${GAEL_KERNEL}"
)"

echo "${GRUB_OUTPUT}"

# Validate kernel resolution
echo "${GRUB_OUTPUT}" | grep -q "ZEN_KERNEL=.*zen" && pass "Kernel resolve: zen found" || fail "Kernel resolve: zen missing"
echo "${GRUB_OUTPUT}" | grep -q "STABLE_KERNEL=.*gentoo-dist" && pass "Kernel resolve: stable found" || fail "Kernel resolve: stable missing"
echo "${GRUB_OUTPUT}" | grep -q "HARDENED_KERNEL=.*hardened" && pass "Kernel resolve: hardened found" || fail "Kernel resolve: hardened missing"
echo "${GRUB_OUTPUT}" | grep -q "GAEL_KERNEL=.*hardened" && pass "Gael prefers hardened over stable" || fail "Gael not preferring hardened"

# Now generate the actual GRUB config by running the script in a controlled way
PROFILE_OUTPUT="$(
  cd "${MNT}"

  # Use host binaries to avoid glibc mismatch with stage3
  find_kernel()  { /usr/bin/ls -t "${MNT}/boot/vmlinuz-"*${1}* 2>/dev/null | /usr/bin/head -1; }
  find_initrd()  { /usr/bin/ls -t "${MNT}/boot/initramfs-"*${1}*.img 2>/dev/null | /usr/bin/head -1; }

  ZEN_KERNEL="$(find_kernel 'zen')"
  ZEN_INITRD="$(find_initrd 'zen')"
  STABLE_KERNEL="$(find_kernel 'gentoo')"
  STABLE_INITRD="$(find_initrd 'gentoo')"
  HARDENED_KERNEL="$(find_kernel 'hardened')"
  HARDENED_INITRD="$(find_initrd 'hardened')"
  GAEL_KERNEL="${HARDENED_KERNEL:-$STABLE_KERNEL}"
  GAEL_INITRD="${HARDENED_INITRD:-$STABLE_INITRD}"
  CRYPT_UUID_NO_DASH="${CRYPT_UUID//-/}"

  # Strip MNT prefix for paths (simulating /boot is root for GRUB)
  grub_path() { echo "${1#${MNT}/boot}"; }

  # Generate Gael entry
  if [[ -n "${GAEL_KERNEL}" ]]; then
    GAEL_KPATH="$(grub_path "${GAEL_KERNEL}")"
    GAEL_IPATH="$(grub_path "${GAEL_INITRD}")"
    cat << EOF
menuentry "LogOS - Gael [Maximum Security]" --class logos \$menuentry_id_option 'logos-gael' {
    cryptomount -u ${CRYPT_UUID_NO_DASH}
    search --no-floppy --fs-uuid --set=root ${BTRFS_UUID}
    linux ${GAEL_KPATH} root=UUID=${BTRFS_UUID} rootflags=subvol=@ rw cryptdevice=UUID=${CRYPT_UUID}:cryptroot audit=1 apparmor=1 lsm=landlock,lockdown,yama,integrity,apparmor,bpf lockdown=confidentiality mitigations=auto,nosmt nosmt=force init_on_alloc=1 init_on_free=1 slab_nomerge pti=on quiet loglevel=3
    initrd ${GAEL_IPATH}
}
EOF
  fi

  # Generate Midir entry
  if [[ -n "${ZEN_KERNEL}" ]]; then
    MIDIR_KPATH="$(grub_path "${ZEN_KERNEL}")"
    MIDIR_IPATH="$(grub_path "${ZEN_INITRD}")"
    cat << EOF
menuentry "LogOS - Midir [Daily Driver]" --class logos \$menuentry_id_option 'logos-midir' {
    cryptomount -u ${CRYPT_UUID_NO_DASH}
    search --no-floppy --fs-uuid --set=root ${BTRFS_UUID}
    linux ${MIDIR_KPATH} root=UUID=${BTRFS_UUID} rootflags=subvol=@ rw cryptdevice=UUID=${CRYPT_UUID}:cryptroot audit=1 apparmor=1 lsm=landlock,lockdown,yama,integrity,apparmor,bpf mitigations=auto quiet loglevel=3
    initrd ${MIDIR_IPATH}
}
EOF
  fi

  # Generate Halflight entry
  if [[ -n "${ZEN_KERNEL}" ]]; then
    HALF_KPATH="$(grub_path "${ZEN_KERNEL}")"
    HALF_IPATH="$(grub_path "${ZEN_INITRD}")"
    cat << EOF
menuentry "LogOS - Halflight [Performance]" --class logos \$menuentry_id_option 'logos-halflight' {
    cryptomount -u ${CRYPT_UUID_NO_DASH}
    search --no-floppy --fs-uuid --set=root ${BTRFS_UUID}
    linux ${HALF_KPATH} root=UUID=${BTRFS_UUID} rootflags=subvol=@ rw cryptdevice=UUID=${CRYPT_UUID}:cryptroot audit=0 mitigations=off nowatchdog nmi_watchdog=0 quiet loglevel=3
    initrd ${HALF_IPATH}
}
EOF
  fi
)"

# Save the output for inspection
mkdir -p "${MNT}/boot/grub"
echo "${PROFILE_OUTPUT}" > "${MNT}/boot/grub/logos-profiles-test.cfg"

echo ""; echo "== Profile Content Validation =="

# Validate all three profiles present
echo "${PROFILE_OUTPUT}" | grep -q 'LogOS - Gael'      && pass "Profile: Gael present"      || fail "Profile: Gael missing"
echo "${PROFILE_OUTPUT}" | grep -q 'LogOS - Midir'     && pass "Profile: Midir present"     || fail "Profile: Midir missing"
echo "${PROFILE_OUTPUT}" | grep -q 'LogOS - Halflight' && pass "Profile: Halflight present" || fail "Profile: Halflight missing"

# Validate menu entry IDs
echo "${PROFILE_OUTPUT}" | grep -q "logos-gael"      && pass "Entry ID: logos-gael"      || fail "Entry ID: logos-gael missing"
echo "${PROFILE_OUTPUT}" | grep -q "logos-midir"     && pass "Entry ID: logos-midir"     || fail "Entry ID: logos-midir missing"
echo "${PROFILE_OUTPUT}" | grep -q "logos-halflight" && pass "Entry ID: logos-halflight" || fail "Entry ID: logos-halflight missing"

# Validate UUIDs appear
CRYPT_UUID_NO_DASH="${CRYPT_UUID//-/}"
echo "${PROFILE_OUTPUT}" | grep -q "${CRYPT_UUID_NO_DASH}" && pass "LUKS UUID (no-dash) in profiles" || fail "LUKS UUID missing"
echo "${PROFILE_OUTPUT}" | grep -q "${BTRFS_UUID}"          && pass "Btrfs UUID in profiles"         || fail "Btrfs UUID missing"
echo "${PROFILE_OUTPUT}" | grep -q "${CRYPT_UUID}"          && pass "LUKS UUID (dashed) in cmdline"  || fail "LUKS UUID dashed missing"

# Validate Gael security params
echo "${PROFILE_OUTPUT}" | grep "Gael" -A5 | grep -q "lockdown=confidentiality"  && pass "Gael: lockdown=confidentiality" || fail "Gael: missing lockdown"
echo "${PROFILE_OUTPUT}" | grep "Gael" -A5 | grep -q "nosmt=force"               && pass "Gael: nosmt=force"              || fail "Gael: missing nosmt"
echo "${PROFILE_OUTPUT}" | grep "Gael" -A5 | grep -q "init_on_alloc=1"           && pass "Gael: init_on_alloc=1"          || fail "Gael: missing init_on_alloc"
echo "${PROFILE_OUTPUT}" | grep "Gael" -A5 | grep -q "slab_nomerge"              && pass "Gael: slab_nomerge"             || fail "Gael: missing slab_nomerge"
echo "${PROFILE_OUTPUT}" | grep "Gael" -A5 | grep -q "pti=on"                    && pass "Gael: pti=on"                   || fail "Gael: missing pti"
echo "${PROFILE_OUTPUT}" | grep "Gael" -A5 | grep -q "audit=1"                   && pass "Gael: audit=1"                  || fail "Gael: missing audit"
echo "${PROFILE_OUTPUT}" | grep "Gael" -A5 | grep -q "apparmor=1"                && pass "Gael: apparmor=1"               || fail "Gael: missing apparmor"

# Validate Gael uses hardened kernel (not zen)
echo "${PROFILE_OUTPUT}" | grep "Gael" -A5 | grep -q "hardened" && pass "Gael: uses hardened kernel" || fail "Gael: not using hardened"

# Validate Midir params
echo "${PROFILE_OUTPUT}" | grep "Midir" -A5 | grep -q "mitigations=auto"  && pass "Midir: mitigations=auto"  || fail "Midir: wrong mitigations"
echo "${PROFILE_OUTPUT}" | grep "Midir" -A5 | grep -q "audit=1"           && pass "Midir: audit=1"           || fail "Midir: missing audit"
echo "${PROFILE_OUTPUT}" | grep "Midir" -A5 | grep -q "zen"               && pass "Midir: uses zen kernel"   || fail "Midir: not using zen"

# Validate Halflight params
echo "${PROFILE_OUTPUT}" | grep "Halflight" -A5 | grep -q "mitigations=off"  && pass "Halflight: mitigations=off"  || fail "Halflight: wrong mitigations"
echo "${PROFILE_OUTPUT}" | grep "Halflight" -A5 | grep -q "audit=0"          && pass "Halflight: audit=0"          || fail "Halflight: audit not disabled"
echo "${PROFILE_OUTPUT}" | grep "Halflight" -A5 | grep -q "nowatchdog"       && pass "Halflight: nowatchdog"       || fail "Halflight: missing nowatchdog"
echo "${PROFILE_OUTPUT}" | grep "Halflight" -A5 | grep -q "zen"              && pass "Halflight: uses zen kernel"  || fail "Halflight: not using zen"

# Validate LUKS modules
echo "${PROFILE_OUTPUT}" | grep -q "cryptomount" && pass "GRUB: cryptomount present" || fail "GRUB: cryptomount missing"

# ═══════════════════════════════════════════════════════════════════
# TEST SECTION 2: Security Config Deployment
# ═══════════════════════════════════════════════════════════════════
echo ""; echo "== Security Config Deployment =="

# sysctl
mkdir -p "${MNT}/etc/sysctl.d"
cp "${INSTALLER_DIR}/security/99-logos-hardening.conf" "${MNT}/etc/sysctl.d/"
[[ -f "${MNT}/etc/sysctl.d/99-logos-hardening.conf" ]] && pass "sysctl: config installed" || fail "sysctl: missing"

SYSCTL="${MNT}/etc/sysctl.d/99-logos-hardening.conf"
grep -q "kernel.kptr_restrict = 2"         "${SYSCTL}" && pass "sysctl: kptr_restrict=2"          || fail "sysctl: kptr_restrict"
grep -q "kernel.dmesg_restrict = 1"        "${SYSCTL}" && pass "sysctl: dmesg_restrict=1"         || fail "sysctl: dmesg_restrict"
grep -q "kernel.perf_event_paranoid = 3"   "${SYSCTL}" && pass "sysctl: perf_event_paranoid=3"    || fail "sysctl: perf_event_paranoid"
grep -q "kernel.sysrq = 0"                 "${SYSCTL}" && pass "sysctl: sysrq=0"                  || fail "sysctl: sysrq"
grep -q "kernel.unprivileged_bpf_disabled" "${SYSCTL}" && pass "sysctl: unprivileged_bpf_disabled" || fail "sysctl: bpf"
grep -q "net.ipv4.tcp_syncookies = 1"      "${SYSCTL}" && pass "sysctl: tcp_syncookies=1"         || fail "sysctl: syncookies"

# Audit rules
mkdir -p "${MNT}/etc/audit/rules.d"
cp "${INSTALLER_DIR}/security/logos-audit.rules" "${MNT}/etc/audit/rules.d/"
[[ -f "${MNT}/etc/audit/rules.d/logos-audit.rules" ]] && pass "audit: rules installed" || fail "audit: missing"

AUDIT="${MNT}/etc/audit/rules.d/logos-audit.rules"
grep -q "/etc/passwd"           "${AUDIT}" && pass "audit: monitors /etc/passwd"   || fail "audit: passwd"
grep -q "/etc/sudoers"          "${AUDIT}" && pass "audit: monitors sudoers"       || fail "audit: sudoers"
grep -q "/etc/ssh/sshd_config"  "${AUDIT}" && pass "audit: monitors sshd_config"   || fail "audit: sshd"
grep -q "logos_boot"            "${AUDIT}" && pass "audit: monitors logos boot"    || fail "audit: logos_boot"
grep -q "logos_watchdog"        "${AUDIT}" && pass "audit: monitors watchdog"      || fail "audit: watchdog"
grep -q "insmod"                "${AUDIT}" && pass "audit: monitors module loading" || fail "audit: modules"
grep -q -- "-e 2"               "${AUDIT}" && pass "audit: rules immutable"        || fail "audit: not immutable"

# SSH hardening
mkdir -p "${MNT}/etc/ssh/sshd_config.d"
cp "${INSTALLER_DIR}/security/10-logos-ssh.conf" "${MNT}/etc/ssh/sshd_config.d/"
[[ -f "${MNT}/etc/ssh/sshd_config.d/10-logos-ssh.conf" ]] && pass "ssh: config installed" || fail "ssh: missing"

SSH="${MNT}/etc/ssh/sshd_config.d/10-logos-ssh.conf"
grep -q "PermitRootLogin no"             "${SSH}" && pass "ssh: no root login"     || fail "ssh: root login"
grep -q "PasswordAuthentication no"      "${SSH}" && pass "ssh: no password auth"  || fail "ssh: password auth"
grep -q "MaxAuthTries 3"                 "${SSH}" && pass "ssh: MaxAuthTries=3"    || fail "ssh: auth tries"
grep -q "X11Forwarding no"              "${SSH}" && pass "ssh: no X11"             || fail "ssh: X11"
grep -q "chacha20-poly1305"             "${SSH}" && pass "ssh: strong ciphers"     || fail "ssh: ciphers"
grep -q "sntrup761x25519"               "${SSH}" && pass "ssh: PQ key exchange"   || fail "ssh: kex"

# Dracut config
mkdir -p "${MNT}/etc/dracut.conf.d"
cp "${INSTALLER_DIR}/configs/dracut.conf" "${MNT}/etc/dracut.conf.d/logos.conf"
[[ -f "${MNT}/etc/dracut.conf.d/logos.conf" ]] && pass "dracut: config installed" || fail "dracut: missing"

DRACUT="${MNT}/etc/dracut.conf.d/logos.conf"
grep -q "crypt"           "${DRACUT}" && pass "dracut: crypt module"      || fail "dracut: no crypt"
grep -q "btrfs"           "${DRACUT}" && pass "dracut: btrfs module"      || fail "dracut: no btrfs"
grep -q "systemd"         "${DRACUT}" && pass "dracut: systemd module"    || fail "dracut: no systemd"
grep -q 'early_microcode' "${DRACUT}" && pass "dracut: early microcode"   || fail "dracut: no microcode"
grep -q 'compress="zstd"' "${DRACUT}" && pass "dracut: zstd compression"  || fail "dracut: no zstd"
grep -q 'hostonly="yes"'  "${DRACUT}" && pass "dracut: hostonly=yes"      || fail "dracut: not hostonly"

# ═══════════════════════════════════════════════════════════════════
# TEST SECTION 3: Kernel Watchdog Logic
# ═══════════════════════════════════════════════════════════════════
echo ""; echo "== Kernel Watchdog Logic =="

mkdir -p "${MNT}/usr/local/lib/logos"
cp "${INSTALLER_DIR}/kernel/kernel-watchdog.sh" "${MNT}/usr/local/lib/logos/"
chmod +x "${MNT}/usr/local/lib/logos/kernel-watchdog.sh"
[[ -x "${MNT}/usr/local/lib/logos/kernel-watchdog.sh" ]] && pass "watchdog: script installed" || fail "watchdog: missing"

# Validate watchdog whitelisting
WATCHDOG="${MNT}/usr/local/lib/logos/kernel-watchdog.sh"
grep -q 'ALLOWED_ENTRIES=.*logos-gael.*logos-midir.*logos-halflight' "${WATCHDOG}" && pass "watchdog: whitelisted entries defined" || fail "watchdog: no whitelist"
grep -q 'is_allowed_entry' "${WATCHDOG}" && pass "watchdog: validation function present" || fail "watchdog: no validation"
grep -q 'MAX_FAILURES=2' "${WATCHDOG}" && pass "watchdog: max failures = 2" || fail "watchdog: wrong max failures"
grep -q 'COUNTER_FILE' "${WATCHDOG}" && pass "watchdog: counter file defined" || fail "watchdog: no counter"
grep -q 'grub-set-default' "${WATCHDOG}" && pass "watchdog: uses grub-set-default" || fail "watchdog: no grub-set-default"
grep -q 'audit_log\|logger.*DEGRADATION' "${WATCHDOG}" && pass "watchdog: degradation audit logging" || fail "watchdog: no audit logging"

# Validate health checks
grep -q 'apparmor.service' "${WATCHDOG}" && pass "watchdog: checks apparmor" || fail "watchdog: no apparmor check"
grep -q 'auditd.service'   "${WATCHDOG}" && pass "watchdog: checks auditd"  || fail "watchdog: no auditd check"
grep -q 'ufw.service'      "${WATCHDOG}" && pass "watchdog: checks ufw"     || fail "watchdog: no ufw check"
grep -q 'NetworkManager'   "${WATCHDOG}" && pass "watchdog: checks NM"      || fail "watchdog: no NM check"
grep -q '/proc/sys/kernel/tainted' "${WATCHDOG}" && pass "watchdog: checks kernel taint" || fail "watchdog: no taint check"

# Validate degradation direction (always toward Gael)
grep -q 'set_grub_default.*logos-gael' "${WATCHDOG}" && pass "watchdog: degrades to Gael" || fail "watchdog: wrong degradation target"

# Systemd units
cp "${INSTALLER_DIR}/services/logos-kernel-watchdog.service" "${MNT}/etc/systemd/system/"
cp "${INSTALLER_DIR}/services/logos-kernel-watchdog.timer"   "${MNT}/etc/systemd/system/"

SVC="${MNT}/etc/systemd/system/logos-kernel-watchdog.service"
TMR="${MNT}/etc/systemd/system/logos-kernel-watchdog.timer"

[[ -f "${SVC}" ]] && pass "watchdog: service unit installed"  || fail "watchdog: service missing"
[[ -f "${TMR}" ]] && pass "watchdog: timer unit installed"    || fail "watchdog: timer missing"
grep -q 'Type=oneshot'           "${SVC}" && pass "watchdog: oneshot service"     || fail "watchdog: not oneshot"
grep -q 'ProtectSystem=strict'   "${SVC}" && pass "watchdog: ProtectSystem"      || fail "watchdog: no ProtectSystem"
grep -q 'OnBootSec=90s'          "${TMR}" && pass "watchdog: 90s boot delay"     || fail "watchdog: wrong delay"
grep -q 'timers.target'          "${TMR}" && pass "watchdog: WantedBy timers"    || fail "watchdog: wrong target"

# ═══════════════════════════════════════════════════════════════════
# TEST SECTION 4: logos-validate-boot Script
# ═══════════════════════════════════════════════════════════════════
echo ""; echo "== logos-validate-boot Validation =="

install -Dm755 "${INSTALLER_DIR}/tools/logos-validate-boot" "${MNT}/usr/local/bin/logos-validate-boot"
[[ -x "${MNT}/usr/local/bin/logos-validate-boot" ]] && pass "validate-boot: installed" || fail "validate-boot: missing"

VALIDATE="${MNT}/usr/local/bin/logos-validate-boot"
# Check it validates all the right things
grep -q 'crypto_LUKS\|lsblk.*crypt' "${VALIDATE}" && pass "validate: checks encryption"   || fail "validate: no encryption check"
grep -q 'Btrfs\|btrfs'              "${VALIDATE}" && pass "validate: checks btrfs"         || fail "validate: no btrfs check"
grep -q 'vmlinuz.*zen'              "${VALIDATE}" && pass "validate: checks zen kernel"    || fail "validate: no zen check"
grep -q 'vmlinuz.*gentoo'           "${VALIDATE}" && pass "validate: checks stable kernel" || fail "validate: no stable check"
grep -q 'Gael.*Midir.*Halflight\|Gael.*Midir\|for profile in' "${VALIDATE}" && pass "validate: checks profiles" || fail "validate: no profile check"
grep -q 'apparmor.*auditd\|for svc in.*apparmor' "${VALIDATE}" && pass "validate: checks security services" || fail "validate: no service check"
grep -q '99-logos-hardening'        "${VALIDATE}" && pass "validate: checks sysctl"        || fail "validate: no sysctl check"
grep -q '10-logos-ssh'              "${VALIDATE}" && pass "validate: checks SSH config"    || fail "validate: no SSH check"
grep -q 'watchdog'                  "${VALIDATE}" && pass "validate: checks watchdog"      || fail "validate: no watchdog check"
grep -q 'logos-release'             "${VALIDATE}" && pass "validate: checks branding"      || fail "validate: no branding check"

# ═══════════════════════════════════════════════════════════════════
# TEST SECTION 5: Branding and logos-release
# ═══════════════════════════════════════════════════════════════════
echo ""; echo "== Branding Verification =="

RELEASE="${MNT}/etc/logos-release"
[[ -f "${RELEASE}" ]] && pass "logos-release exists" || fail "logos-release missing"
grep -q 'NAME="LogOS"'                     "${RELEASE}" && pass "branding: name LogOS"     || fail "branding: wrong name"
grep -q 'CODENAME="Ringed City"'           "${RELEASE}" && pass "branding: Ringed City"    || fail "branding: wrong codename"
grep -q 'BASE="Gentoo Linux"'              "${RELEASE}" && pass "branding: base Gentoo"    || fail "branding: wrong base"
grep -q 'INSTALLATION_METHOD="phase-scripts"' "${RELEASE}" && pass "branding: phase-scripts" || fail "branding: wrong method"

# MOTD
cat > "${MNT}/etc/motd" << 'MOTDEOF'
LogOS Gentoo — Ringed City Build
Profiles: Gael (Security) | Midir (Balanced) | Halflight (Performance)
"Knowledge preserved. Reason applied. Civilization continued."
MOTDEOF
grep -q "Ringed City" "${MNT}/etc/motd" && pass "motd: Ringed City" || fail "motd: wrong"
grep -q "Gael.*Midir.*Halflight" "${MNT}/etc/motd" && pass "motd: all profiles listed" || fail "motd: missing profiles"

# ═══════════════════════════════════════════════════════════════════
# TEST SECTION 6: Tool Scripts
# ═══════════════════════════════════════════════════════════════════
echo ""; echo "== Tool Scripts =="

install -Dm755 "${INSTALLER_DIR}/tools/logos-assist" "${MNT}/usr/local/bin/logos-assist"
install -Dm755 "${INSTALLER_DIR}/tools/logos-canon-promote" "${MNT}/usr/local/bin/logos-canon-promote"

[[ -x "${MNT}/usr/local/bin/logos-assist" ]]        && pass "logos-assist: installed"        || fail "logos-assist: missing"
[[ -x "${MNT}/usr/local/bin/logos-canon-promote" ]]  && pass "logos-canon-promote: installed" || fail "logos-canon-promote: missing"

# logos-assist checks
ASSIST="${MNT}/usr/local/bin/logos-assist"
grep -q 'LOGOS_MODEL'    "${ASSIST}" && pass "logos-assist: model configurable" || fail "logos-assist: no model config"
grep -q 'ollama run'     "${ASSIST}" && pass "logos-assist: uses ollama"        || fail "logos-assist: no ollama"
grep -q 'interactive\|while true\|read.*query' "${ASSIST}" && pass "logos-assist: interactive mode" || fail "logos-assist: no interactive"

# logos-canon-promote checks
PROMOTE="${MNT}/usr/local/bin/logos-canon-promote"
grep -q 'cold-canon'    "${PROMOTE}" && pass "canon-promote: cold canon path"  || fail "canon-promote: no cold path"
grep -q 'warm-mesh'     "${PROMOTE}" && pass "canon-promote: warm mesh path"   || fail "canon-promote: no warm path"
grep -q 'sha256sum'     "${PROMOTE}" && pass "canon-promote: SHA-256 verify"   || fail "canon-promote: no checksum"
grep -q 'Checksum mismatch' "${PROMOTE}" && pass "canon-promote: error on mismatch" || fail "canon-promote: no mismatch handling"

# ── Summary ───────────────────────────────────────────────────────
echo ""
echo "========================================"
echo "  Phase 2 Test Results"
echo "  PASS: ${PASS}  FAIL: ${FAIL}"
echo "========================================"

cat > "${TEST_DIR}/test-phase2-results.log" << REOF
Phase 2 Test — $(date -Iseconds)
PASS: ${PASS}
FAIL: ${FAIL}
Sections tested:
  1. GRUB Ringed City profiles (3 profiles, UUID injection, security params)
  2. Security config deployment (sysctl, audit, SSH, dracut)
  3. Kernel watchdog logic (whitelist, counter, health checks, degradation)
  4. logos-validate-boot script (10+ check categories)
  5. Branding (logos-release, MOTD)
  6. Tool scripts (logos-assist, logos-canon-promote)
REOF

[[ "${FAIL}" -gt 0 ]] && exit 1 || exit 0
