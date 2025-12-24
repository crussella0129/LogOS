"""
LogOS Installation Profile for archinstall

Installs LogOS packages and enables baseline services.
"""

from archinstall.default_profiles.minimal import MinimalProfile


class LogOSProfile(MinimalProfile):
    def __init__(self) -> None:
        super().__init__()
        self.name = "LogOS"
        self.description = "Ontology Substrate OS - Ringed City Build"

    @property
    def packages(self) -> list[str]:
        return [
            "base",
            "base-devel",
            "linux",
            "linux-headers",
            "linux-lts",
            "linux-lts-headers",
            "linux-zen",
            "linux-zen-headers",
            "linux-firmware",
            "linux-firmware-whence",
            "btrfs-progs",
            "cryptsetup",
            "grub",
            "efibootmgr",
            "os-prober",
            "apparmor",
            "audit",
            "ufw",
            "networkmanager",
            "vim",
            "nano",
            "git",
            "wget",
            "curl",
            "rsync",
            "htop",
            "tmux",
            "zsh",
            "man-db",
            "man-pages",
            "snapper",
            "snap-pac",
            "grub-btrfs",
        ]

    @property
    def default_services(self) -> list[str]:
        return [
            "NetworkManager",
            "apparmor",
            "auditd",
            "ufw",
            "grub-btrfsd",
        ]

    def post_install(self, install_session) -> None:
        for service in self.default_services:
            install_session.enable_service(f"{service}.service")

        release_content = """\
NAME=\"LogOS\"
VERSION=\"2025.8\"
CODENAME=\"Ringed City\"
BASE=\"Arch Linux\"
"""
        release_path = f"{install_session.target}/etc/logos-release"
        with open(release_path, "w", encoding="utf-8") as handle:
            handle.write(release_content)

        self._apply_sysctl_hardening(install_session)

    def _apply_sysctl_hardening(self, install_session) -> None:
        hardening = """\
# LogOS Kernel Hardening
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.perf_event_paranoid = 3
kernel.sysrq = 0
kernel.unprivileged_bpf_disabled = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.tcp_syncookies = 1
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
"""
        sysctl_path = f"{install_session.target}/etc/sysctl.d/99-logos-hardening.conf"
        with open(sysctl_path, "w", encoding="utf-8") as handle:
            handle.write(hardening)
