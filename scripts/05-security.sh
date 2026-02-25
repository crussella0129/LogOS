#!/usr/bin/env bash
# 05-security.sh — Security Hardening
# Context: Inside chroot OR booted system (auto-detects).
# Applies sysctl hardening, AppArmor, audit, UFW, fail2ban, SSH hardening.
#
# Ported from: phase2-transform.sh:188-214 (sysctl + UFW), master spec section 8

LOGOS_SECTION="05-security"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f /root/LogOS/lib/common.sh ]]; then
  source /root/LogOS/lib/common.sh
  load_config /root/LogOS/logos.conf
else
  source "${SCRIPT_DIR}/../lib/common.sh"
  load_config "${SCRIPT_DIR}/../logos.conf"
fi

require_root

# ── Sysctl kernel hardening ────────────────────────────────────────
log "Applying sysctl hardening"
cat > /etc/sysctl.d/99-logos-hardening.conf << 'EOF'
# LogOS kernel hardening
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.perf_event_paranoid = 3
kernel.sysrq = 0
kernel.unprivileged_bpf_disabled = 1
kernel.yama.ptrace_scope = 2
net.core.bpf_jit_harden = 2
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.icmp_echo_ignore_all = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
EOF

# Apply immediately if not in chroot
if [[ "$(stat -c %d:%i /)" != "$(stat -c %d:%i /proc/1/root 2>/dev/null)" ]] 2>/dev/null; then
  log "In chroot — sysctl will apply on first boot"
else
  sysctl --system >/dev/null 2>&1
fi
log_ok "Sysctl hardening applied"

# ── AppArmor + Audit ──────────────────────────────────────────────
log "Enabling AppArmor and audit"
systemctl enable apparmor.service 2>/dev/null || true
systemctl enable auditd.service 2>/dev/null || true

# Write basic audit rules
mkdir -p /etc/audit/rules.d
cat > /etc/audit/rules.d/logos.rules << 'EOF'
# LogOS audit rules
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/ssh/sshd_config -p wa -k sshd
-w /var/log/auth.log -p wa -k auth
EOF
log_ok "AppArmor and audit configured"

# ── UFW firewall ───────────────────────────────────────────────────
log "Configuring UFW firewall"
install_pkgs ufw 2>/dev/null || true
systemctl enable ufw.service 2>/dev/null || true
ufw default deny incoming
ufw default allow outgoing

if [[ "${LOGOS_SSHD:-0}" == "1" ]] && [[ "${LOGOS_UFW_ALLOW_SSH:-0}" == "1" ]]; then
  log "Allowing SSH through firewall"
  ufw allow ssh
fi

ufw --force enable
log_ok "UFW configured (default deny incoming, allow outgoing)"

# ── fail2ban ───────────────────────────────────────────────────────
if [[ "${LOGOS_FAIL2BAN:-1}" == "1" ]]; then
  log "Configuring fail2ban"
  install_pkgs fail2ban 2>/dev/null || true

  mkdir -p /etc/fail2ban/jail.d
  cat > /etc/fail2ban/jail.d/logos.conf << 'EOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd

[sshd]
enabled = true
port    = ssh
filter  = sshd
maxretry = 3
EOF

  systemctl enable fail2ban.service 2>/dev/null || true
  log_ok "fail2ban configured"
else
  log "fail2ban disabled in config — skipping"
fi

# ── SSH hardening ──────────────────────────────────────────────────
if [[ "${LOGOS_SSHD:-0}" == "1" ]]; then
  log "Applying SSH hardening"

  mkdir -p /etc/ssh/sshd_config.d
  cat > /etc/ssh/sshd_config.d/10-logos.conf << 'EOF'
# LogOS SSH hardening
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

  systemctl enable sshd.service 2>/dev/null || true
  log_ok "SSH hardened and enabled"
else
  log "SSH daemon disabled in config — skipping"
fi

log_ok "Security hardening complete. Proceed to 06-desktop.sh (after reboot)"
