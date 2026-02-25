# LogOS Build Guide

**Ontology Substrate Operating System — Literate Build Guide**

Version: 2025.8 (Ringed City)
Architecture: x86_64
Base: Arch Linux

> *"A civilization does not collapse when it loses data. It collapses when it loses procedural knowledge."*

---

## How to Use This Guide

This document is the **source of truth** for building a LogOS system. Each section explains *what* you're doing and *why*, then references a numbered companion script that automates the process.

You have two paths:

1. **Follow the guide + run scripts** (recommended): Read each section to understand the rationale, then run the companion script.
2. **Manual execution**: Use the guide as a reference and type every command yourself.

The companion scripts live in `scripts/` and share common functions via `lib/common.sh` and `lib/detect.sh`. All user choices are centralized in `logos.conf`.

### Prerequisites

- A working internet connection
- An x86_64 system with UEFI support
- At least 120 GB of storage (512 GB+ recommended)
- A USB drive (2 GB+) or virtual machine
- A clone of this repository

---

## 1. Preparation

Before touching any hardware, you need the Arch Linux ISO, a way to boot it, and your `logos.conf` configuration.

### 1.1 Download and Verify the ISO

Always verify the ISO. A compromised installer is game over before you start.

```bash
# Download the ISO and verification files
wget https://mirrors.kernel.org/archlinux/iso/latest/archlinux-x86_64.iso
wget https://mirrors.kernel.org/archlinux/iso/latest/archlinux-x86_64.iso.sig
wget https://mirrors.kernel.org/archlinux/iso/latest/sha256sums.txt

# Verify checksum
sha256sum -c sha256sums.txt --ignore-missing

# Verify GPG signature
gpg --keyserver-options auto-key-retrieve --verify archlinux-x86_64.iso.sig
```

If the GPG signature fails, **do not proceed**. Re-download from a different mirror.

### 1.2 Create Installation Media

#### USB Drive (Bare Metal)

```bash
# Identify your USB device — get this wrong and you destroy the wrong disk
lsblk

# Write ISO (replace sdX with your device)
sudo dd bs=4M if=archlinux-x86_64.iso of=/dev/sdX conv=fsync oflag=direct status=progress
sync
```

Alternatively, use [Ventoy](https://ventoy.net/) — it allows multiple ISOs on a single USB.

#### Virtual Machine

**QEMU/KVM:**

```bash
qemu-img create -f qcow2 logos.qcow2 120G

qemu-system-x86_64 \
  -enable-kvm \
  -m 8192 \
  -cpu host \
  -smp 4 \
  -drive file=logos.qcow2,format=qcow2 \
  -cdrom archlinux-x86_64.iso \
  -boot d \
  -bios /usr/share/ovmf/OVMF.fd \
  -vga virtio \
  -device virtio-net-pci,netdev=net0 \
  -netdev user,id=net0
```

**VirtualBox:** Create VM → Type: Linux, Arch Linux 64-bit → 8 GB RAM → 120 GB VDI → Enable EFI in System settings → Attach ISO.

**VMware:** New VM → Linux, Other Linux 5.x 64-bit → 8 GB RAM, 4 CPUs → Firmware type: UEFI → Attach ISO.

### 1.3 Configure `logos.conf`

```bash
cp logos.conf.example logos.conf
# Edit logos.conf with your hardware and preferences
```

At minimum, set:

| Variable | What to set |
|----------|-------------|
| `LOGOS_DISK` | Target disk device (e.g., `/dev/nvme0n1`) |
| `LOGOS_HOSTNAME` | Machine name |
| `LOGOS_USERNAME` | Your login username |
| `LOGOS_TIMEZONE` | Your timezone (e.g., `America/New_York`) |

Every other setting has a sane default. Review the full file for optional features like package categories and LLM support.

---

## 2. Live Environment

Boot the USB (or VM) and select "Arch Linux install medium (x86_64, UEFI)". You'll land at a root shell.

### What this checks

- **UEFI mode**: LogOS requires UEFI for Secure Boot compatibility and the GPT partition scheme. Legacy BIOS is not supported.
- **Network**: Required for downloading packages. Wired is simplest; wireless uses `iwctl`.
- **Clock sync**: Incorrect time causes GPG signature verification failures.
- **Pacman keyring**: Stale keyrings cause package installation failures.

### Network setup (if needed)

```bash
# Wired — usually auto-configured
dhcpcd

# Wireless
iwctl
# Inside iwctl:
#   device list
#   station wlan0 scan
#   station wlan0 get-networks
#   station wlan0 connect "YourNetworkName"
#   exit
```

### → `scripts/00-verify-env.sh`

```bash
sudo bash scripts/00-verify-env.sh
```

This script checks all of the above, refreshes the keyring, optionally optimizes mirrors (if `LOGOS_MIRROR_COUNTRY` is set), and displays your `logos.conf` summary for review.

---

## 3. Disk Setup

This is the most critical and **destructive** step. Everything on the target disk will be erased.

### Partition Scheme

LogOS uses a three-partition GPT layout:

| Partition | Size | Type | Filesystem | Mount |
|-----------|------|------|------------|-------|
| EFI | 1 GB | EF00 | FAT32 | `/boot/efi` |
| Boot | 4 GB | 8300 | ext4 | `/boot` |
| Root | Remainder | 8309 | LUKS2 → Btrfs | `/` |

**Why 4 GB for `/boot`?** The triple-kernel architecture generates six initramfs images (3 kernels × 2 initramfs each). Running out of `/boot` space during kernel updates is a common failure mode.

**Why a separate EFI partition?** GRUB's EFI stub lives here. Keeping it separate from `/boot` means the EFI System Partition only holds the bootloader, not kernel images — which matters for Secure Boot signing.

### LUKS2 Encryption

LogOS uses LUKS2 with Argon2id as the key derivation function. Argon2id is resistant to both GPU-based and side-channel attacks, making it superior to PBKDF2 for passphrase-derived keys.

The default parameters (`aes-xts-plain64`, 512-bit key, `sha512`, `argon2id`) are strong. Change them only if you have a specific reason.

### Btrfs Subvolume Layout

| Subvolume | Mount Point | Purpose |
|-----------|-------------|---------|
| `@` | `/` | Root filesystem |
| `@home` | `/home` | User data |
| `@canon` | `/srv/cold-canon` | Cold Canon archival (copies=2) |
| `@mesh` | `/srv/warm-mesh` | Warm Mesh sync workspace |
| `@snapshots` | `/.snapshots` | Snapper snapshots |
| `@log` | `/var/log` | Logs (nodatacow for write performance) |
| `@pkg` | `/var/cache/pacman/pkg` | Package cache |

**Why separate subvolumes?** Each subvolume can have independent snapshot policies, mount options, and backup schedules. `@log` uses `nodatacow` because log files are write-heavy and don't benefit from copy-on-write. `@canon` uses `copies=2` for bitrot protection on archival data.

### → `scripts/01-disk-setup.sh`

```bash
sudo bash scripts/01-disk-setup.sh
```

This script partitions the disk with `sgdisk`, formats LUKS2 (prompts for passphrase), creates Btrfs with all seven subvolumes, and mounts everything at `/mnt`.

---

## 4. Base Install

With filesystems mounted, we install the minimum packages needed to boot.

### Package Tiers

LogOS uses a tiered installation strategy:

**Tier 0 (Boot-Critical):** Only packages required to reach a login prompt. If Tier 0 fails, debugging is trivial because the surface area is tiny.

- `base`, `linux`, `linux-firmware`, `linux-headers` — kernel and core system
- `linux-lts`, `linux-zen` — additional kernels for Ringed City profiles
- `grub`, `efibootmgr` — bootloader
- CPU microcode (`intel-ucode` or `amd-ucode`) — auto-detected
- `btrfs-progs`, `cryptsetup` — filesystem and encryption tools
- `networkmanager` — post-boot connectivity
- `sudo`, `nano`, `man-db`, `man-pages` — bare essentials

**Tier 1 (Security Infrastructure):** Installed immediately after Tier 0 because security should be configured *before* first boot, not after.

- `apparmor`, `audit` — mandatory access control + audit logging
- `ufw` — firewall
- `openssh` — remote access (disabled by default)
- `fail2ban` (optional) — brute-force protection

### fstab Generation

`genfstab` reads the current mount state and writes `/etc/fstab`.

### → `scripts/02-base-install.sh`

```bash
sudo bash scripts/02-base-install.sh
```

This script runs `pacstrap` for Tier 0, installs Tier 1 via `arch-chroot`, generates fstab, and copies the LogOS configuration into the new system at `/root/LogOS/`.

---

## 5. Chroot Configuration

Now enter the new system to configure it before first boot.

```bash
arch-chroot /mnt
```

Inside the chroot, you'll set the system identity (timezone, locale, hostname, users) and build the initramfs.

### mkinitcpio HOOKS

The hook order in `mkinitcpio.conf` is critical:

```
HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt btrfs filesystems fsck)
```

Key ordering rules:
- `keyboard` and `keymap` must come **before** `encrypt` — otherwise you can't type your LUKS passphrase
- `encrypt` must come **before** `filesystems` — the LUKS container must be opened before Btrfs can mount
- `btrfs` must come **before** `filesystems` — enables Btrfs multi-device support
- `microcode` is placed early for CPU errata fixes during early boot

### → `scripts/03-chroot-setup.sh`

```bash
# Run inside the chroot
bash /root/LogOS/03-chroot-setup.sh
```

This script configures timezone, locale, keymap, hostname, creates your user, writes `mkinitcpio.conf`, and runs `mkinitcpio -P` to generate initramfs for all installed kernels.

**Note:** You'll be prompted to set passwords for root and your user interactively.

---

## 6. Bootloader

GRUB is the bootloader, configured with LUKS2 encryption support and the Ringed City boot profiles.

### Ringed City Profiles

The three profiles are named after bosses from Dark Souls 3's "The Ringed City" DLC — each representing a different balance of defense and aggression:

| Profile | Kernel | Security | Use Case | Perf. Impact |
|---------|--------|----------|----------|-------------|
| **Gael** | linux-lts | Maximum — lockdown, no SMT, full LSM, init_on_alloc/free | Hostile environments, border crossings | ~15-30% |
| **Midir** | linux-zen | Balanced — auto mitigations, AppArmor, audit | Daily driver, general use | ~2-5% |
| **Halflight** | linux-zen | Minimal — mitigations off, no audit | Gaming, media production, HPC | None |

**Gael** (Slave Knight Gael) represents ultimate resilience through adversity. He uses `linux-lts` for maximum stability, `lockdown=confidentiality` to prevent runtime kernel modification, and `nosmt=force` to disable hyper-threading (Spectre mitigation).

**Midir** (Darkeater Midir) balances power with calculated risk. `linux-zen` provides better scheduling and interactivity for desktop use, while `mitigations=auto` applies the kernel's recommended security patches.

**Halflight** (Spear of the Church) prioritizes speed. `mitigations=off` removes all CPU vulnerability mitigations for maximum performance. Use only in trusted environments where the threat model permits it.

### Kernel Parameters Deep-Dive

Key parameters used across profiles:

| Parameter | Gael | Midir | Halflight | Purpose |
|-----------|------|-------|-----------|---------|
| `cryptdevice=UUID=...:cryptroot` | ✓ | ✓ | ✓ | LUKS unlock at boot |
| `apparmor=1` | ✓ | ✓ | — | Enable AppArmor LSM |
| `audit=1` | ✓ | ✓ | — | Enable audit subsystem |
| `lsm=...` | ✓ | ✓ | — | LSM stack ordering |
| `lockdown=confidentiality` | ✓ | — | — | Prevent kernel modification |
| `mitigations=auto,nosmt` | ✓ | — | — | All CPU mitigations + SMT off |
| `mitigations=auto` | — | ✓ | — | Recommended mitigations only |
| `mitigations=off` | — | — | ✓ | No mitigations (performance) |
| `init_on_alloc=1 init_on_free=1` | ✓ | — | — | Zero memory on alloc/free |
| `slab_nomerge` | ✓ | — | — | Prevent slab merging (hardening) |

### → `scripts/04-bootloader.sh`

```bash
# Run inside the chroot
bash /root/LogOS/04-bootloader.sh
```

This script writes GRUB defaults, installs GRUB to the EFI partition, creates the `41_logos_profiles` script with baked-in UUIDs, disables the default `10_linux` generator, and runs `grub-mkconfig`.

---

## 7. Security Hardening

Security in LogOS is configured *before* first boot — it's not an afterthought bolted on later.

### Defense in Depth

LogOS implements multiple overlapping security layers:

1. **Disk encryption** (LUKS2) — protects data at rest
2. **Kernel hardening** (sysctl) — restricts information leaks and attack surface
3. **AppArmor** — mandatory access control per-application
4. **Audit** — logs security-relevant events
5. **UFW** — network firewall (default deny incoming)
6. **fail2ban** — automatic IP banning on brute-force attempts
7. **SSH hardening** — key-only auth, no root login

### Sysctl Hardening

The `99-logos-hardening.conf` file restricts kernel information exposure:

| Setting | Value | Purpose |
|---------|-------|---------|
| `kernel.kptr_restrict` | 2 | Hide kernel pointers from all users |
| `kernel.dmesg_restrict` | 1 | Restrict dmesg to root |
| `kernel.perf_event_paranoid` | 3 | Restrict perf events |
| `kernel.sysrq` | 0 | Disable magic SysRq key |
| `kernel.unprivileged_bpf_disabled` | 1 | Block unprivileged BPF |
| `net.ipv4.tcp_syncookies` | 1 | SYN flood protection |
| `net.ipv4.conf.all.rp_filter` | 1 | Reverse path filtering |

### SSH Hardening (if enabled)

When `LOGOS_SSHD=1`, the SSH daemon is configured with:

- `PermitRootLogin no` — root cannot SSH in
- `PasswordAuthentication no` — keys only (no brute-force surface)
- `MaxAuthTries 3` — lock out after 3 failed attempts
- `ClientAliveInterval 300` — disconnect idle sessions

### → `scripts/05-security.sh`

```bash
# Run inside the chroot (or on the booted system)
bash /root/LogOS/05-security.sh
```

This script writes sysctl hardening, configures AppArmor + audit rules, sets up UFW, and optionally configures fail2ban and SSH hardening based on your `logos.conf` settings.

---

## 8. First Boot

Everything before this point happens in the live environment or chroot. Now it's time to reboot into your LogOS system.

### Exit and Unmount

```bash
# Exit the chroot
exit

# Unmount all filesystems
umount -R /mnt

# Reboot (remove USB when prompted)
reboot
```

### GRUB Menu

On reboot, GRUB presents the Ringed City profiles:

```
LogOS - Gael [Maximum Security]
LogOS - Midir [Daily Driver]
LogOS - Halflight [Performance]
LogOS Recovery Options ►
```

Select **Midir** for first boot (balanced default).

### LUKS Unlock

You'll be prompted for your LUKS passphrase. This happens at two stages:

1. **GRUB stage**: GRUB unlocks the encrypted partition to find kernel images. This may appear slow — GRUB's cryptographic implementation is not optimized.
2. **initramfs stage**: The `encrypt` hook unlocks the partition again for the actual root mount. This is faster.

After unlocking, you should reach a login prompt. Log in with your username and password.

---

## 9. Desktop

After the first successful boot, install the desktop environment and apply the color theme.

### Multi-Desktop Architecture

LogOS supports four desktop environments, controlled by `LOGOS_DESKTOP` in `logos.conf`:

| Desktop | Type | Login Manager | Default Terminal | Use Case |
|---------|------|---------------|-----------------|----------|
| **Hyprland** (default) | Wayland compositor | greetd + tuigreet | kitty | Cyberdeck experience — tiling, animations, modern Wayland |
| **KDE Plasma** | Full desktop | SDDM | kitty | Traditional full-featured desktop with GUI tools |
| **Sway** | Wayland compositor | greetd + tuigreet | alacritty | i3-compatible Wayland — minimal, stable, proven |
| **i3** | X11 tiling WM | LightDM | alacritty | Classic X11 tiling — maximum compatibility |

**Why Hyprland as default?** Hyprland is a dynamic Wayland compositor with smooth animations, per-monitor workspaces, and a modern feature set. It represents the "cyberdeck superfluid" philosophy — fast, keyboard-driven, visually distinctive. If you need maximum stability or X11, choose Sway or i3.

### The Ringed City Theme

The default color theme is **Ringed City** — a Dark Souls aesthetic inspired by "The Ringed City" DLC. Ash backgrounds, ember/gold accents (the First Flame), crimson highlights (Gael's blood), ashen blue-grey secondary tones.

Three themes ship with LogOS, controlled by `LOGOS_THEME`:

| Theme | Aesthetic | Accent Color |
|-------|-----------|-------------|
| **ringed-city** (default) | Ash + ember gold | `#c78f40` (First Flame) |
| **catppuccin-mocha** | Warm pastels | `#cba6f7` (Mauve) |
| **dracula** | Classic dark | `#bd93f9` (Purple) |

Themes are applied at install time via template substitution — every dotfile uses `@@THEME_*@@` placeholders that are replaced with the selected palette's colors.

### Desktop Stack

All desktops share a common foundation:

**Shared packages (all desktops):**
- **Audio**: Pipewire + ALSA/Pulse/JACK bridges + Wireplumber
- **Fonts**: Noto (CJK + emoji), Liberation, DejaVu, Fira Code, JetBrains Mono
- **Utilities**: xdg-user-dirs, xdg-utils
- **GPU drivers**: Auto-detected (NVIDIA, AMD, Intel)

**Shared dotfiles (all desktops):**
- Terminal config (kitty and/or alacritty)
- Starship prompt
- GTK 3/4 settings (dark theme, cursor, icon theme)

### GPU Detection

The script auto-detects your GPU(s) via `lspci` and installs appropriate drivers:

| GPU | Packages | Notes |
|-----|----------|-------|
| NVIDIA | `nvidia nvidia-utils nvidia-settings nvidia-lts` | Proprietary; Wayland env vars auto-configured for Hyprland/Sway |
| AMD | `mesa vulkan-radeon libva-mesa-driver` | Open-source, recommended |
| Intel | `mesa vulkan-intel intel-media-driver` | Open-source, integrated GPUs |

For NVIDIA on Wayland (Hyprland/Sway), the script writes environment variables to `/etc/environment.d/logos-nvidia.conf` to enable hardware acceleration and fix cursor rendering.

### Configuration

Set your desktop and theme in `logos.conf` before running the script:

```bash
# In logos.conf:
LOGOS_DESKTOP="hyprland"     # hyprland, kde, sway, i3
LOGOS_THEME="ringed-city"    # ringed-city, catppuccin-mocha, dracula
LOGOS_TERMINAL=""            # kitty, alacritty (empty = desktop default)
```

### → `scripts/06-desktop.sh`

```bash
sudo bash scripts/06-desktop.sh
```

This script:
1. Loads the selected theme palette
2. Installs shared packages (Pipewire, fonts, GPU drivers)
3. Installs desktop-specific packages and login manager
4. Deploys themed dotfiles to `~/.config/`
5. Enables the login manager service

Reboot to reach the graphical login. For Hyprland/Sway, you'll see the tuigreet TUI login. For KDE, you'll see SDDM. For i3, you'll see LightDM.

---

## 10. Package Modules

LogOS organizes optional software into seven categories, each controlled by a `LOGOS_PKG_*` toggle in `logos.conf`.

| Category | Toggle | Key Packages |
|----------|--------|-------------|
| **Office** | `LOGOS_PKG_OFFICE` | LibreOffice, Thunderbird, Firefox, Chromium, Obsidian, Zotero |
| **Development** | `LOGOS_PKG_DEV` | VS Code, Git, Python, Node.js, Docker |
| **Security** | `LOGOS_PKG_SECURITY` | Wireshark, nmap, hashcat, Metasploit (AUR), Burp Suite (AUR) |
| **Radio/SAR** | `LOGOS_PKG_RADIO` | GQRX, GNU Radio, Direwolf, Xastir, SDRangel (AUR) |
| **Gaming** | `LOGOS_PKG_GAMING` | Steam, Lutris, Wine, MangoHud |
| **Media** | `LOGOS_PKG_MEDIA` | VLC, mpv, OBS, Kdenlive, GIMP, Inkscape, Audacity |
| **Engineering** | `LOGOS_PKG_ENGINEERING` | FreeCAD, OpenSCAD, KiCad, Blender, Fusion 360 (AUR) |

### AUR Trust Model

Some packages (Metasploit, Burp Suite, Fusion 360, SDRangel, CHIRP) come from the Arch User Repository. AUR packages are:

- **Not officially supported** by Arch Linux
- **Built from source** on your machine (via `makepkg`)
- **Community-maintained** — review PKGBUILDs before installing

The script uses `yay` as the AUR helper, installed automatically when needed. AUR operations run as your unprivileged user (never root).

### → `scripts/07-packages.sh`

```bash
sudo bash scripts/07-packages.sh
```

---

## 11. Knowledge Infrastructure

The knowledge layer is what makes LogOS more than just another Arch install. It implements a three-tier information topology designed for resilience.

### Cold / Warm / Hot Topology

```
┌─────────────────────────────────────────────────────────────────┐
│  HOT WORKSPACE (/srv/hot-workspace)                              │
│  Active work area. Fully mutable. Standard backup policies.      │
├─────────────────────────────────────────────────────────────────┤
│  WARM MESH (/srv/warm-mesh)                                      │
│  Shared/syncing data (Syncthing). Mutable with version control.  │
├─────────────────────────────────────────────────────────────────┤
│  COLD CANON (/srv/cold-canon)                                    │
│  Archival knowledge. Btrfs copies=2 for bitrot protection.       │
│  Promotion pipeline: Hot → Warm → Cold (with review).            │
│  Subdirs: documents/ software/ datasets/ media/                  │
└─────────────────────────────────────────────────────────────────┘
```

**Cold Canon** is the core of LogOS's knowledge preservation mission. Data here is stored with `copies=2` (Btrfs stores two copies of each extent), providing protection against silent data corruption. Think of it as your civilization's library — the content that must survive.

### Ollama (Local LLM)

When `LOGOS_OLLAMA=1`, the script installs [Ollama](https://ollama.com/) and pulls the models specified in `LOGOS_OLLAMA_MODELS`. Default models:

- `llama3.1:8b` — general-purpose reasoning
- `qwen2.5:7b` — strong coding and multilingual
- `mistral:7b` — fast inference, good for chat

The `logos-assist` CLI tool provides a quick interface:

```bash
# Single query
logos-assist "Explain the Btrfs copy-on-write mechanism"

# Interactive mode
logos-assist
```

### Kiwix (Offline Documentation)

[Kiwix](https://kiwix.org/) provides offline access to Wikipedia, Stack Overflow, Arch Wiki, and other knowledge bases via compressed ZIM files. Essential for operation without internet.

### → `scripts/08-knowledge.sh`

```bash
sudo bash scripts/08-knowledge.sh
```

---

## 12. Validation & Recovery

### Post-Build Validation

The validation script runs read-only checks across every major subsystem:

- **Boot**: UEFI mode, GRUB installed, all kernels present
- **Encryption**: LUKS active, `cryptdevice` in kernel command line
- **Filesystem**: All subvolumes mounted, compression enabled, no Btrfs errors
- **Security**: AppArmor, audit, UFW running; kernel hardening applied
- **Network**: NetworkManager active, firewall enabled
- **Snapshots**: Snapper configured and running
- **Knowledge**: Directory structure, Ollama, branding

### → `scripts/09-validate.sh`

```bash
sudo bash scripts/09-validate.sh
```

A clean build should show all passes with possible warnings for optional features (like Snapper, which requires manual configuration).

### Snapper Setup (Post-Validation)

Configure automatic snapshots after validation:

```bash
# Install snapshot tools
sudo pacman -S --needed snapper snap-pac grub-btrfs

# Create root configuration
sudo snapper -c root create-config /

# Enable automatic snapshots
sudo systemctl enable snapper-timeline.timer
sudo systemctl enable snapper-cleanup.timer
sudo systemctl enable grub-btrfsd.service
```

### Recovery Procedures

If something goes wrong, boot from the Arch ISO and follow these steps:

```bash
# 1. Open encrypted volume
cryptsetup open /dev/sdX3 cryptroot

# 2. Mount root subvolume
mount -o subvol=@ /dev/mapper/cryptroot /mnt
mount /dev/sdX2 /mnt/boot
mount /dev/sdX1 /mnt/boot/efi

# 3. Chroot in
arch-chroot /mnt

# 4. Fix the problem (reinstall GRUB, regenerate initramfs, etc.)

# 5. Exit, unmount, reboot
exit
umount -R /mnt
reboot
```

For detailed recovery procedures (GRUB, encrypt hook, kernel panic, Btrfs corruption, snapshot rollback), see [Appendix: Troubleshooting](appendices/troubleshooting.md).

---

## Appendices

- [Threat Model & Security Architecture](appendices/threat-model.md) — Formal threat table, security boundaries, profile selection guide
- [Hardware Compatibility](appendices/hardware-compat.md) — Verified hardware, GPU decision matrix, known issues
- [Troubleshooting](appendices/troubleshooting.md) — Failure modes, recovery procedures, emergency quick reference
