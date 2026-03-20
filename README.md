# LogOS — Ontology Substrate Operating System

**Version:** 2025.8 (Ringed City)
**Base:** Artix Linux (OpenRC) | **Arch:** x86_64 | **License:** GPLv3

> *"A civilization does not collapse when it loses data. It collapses when it loses procedural knowledge."*

LogOS is a hardened, encrypted, offline-capable Artix Linux (OpenRC) system with Animus local LLM inference (<https://github.com/crussella0129/Animus>) and a three-tier knowledge preservation topology that includes the GitGael Survival Repo (<https://github.com/crussella0129/GitGael>). It ships with a cyberdeck-first desktop (Hyprland) with a theme and color scheme fitting the end of the world (from Dark Souls 3 at least). **No systemd** — LogOS uses OpenRC for init, elogind for session management, and plain shell scripts for service configuration.

This document is the **source of truth** for building a LogOS system. Each section explains *what* you're doing and *why*, then gives the exact commands to run. The companion scripts automate each step; you can also use this guide as a reference for manual execution.

---

## What You Get

- **Hyprland cyberdeck desktop** with Waybar, Rofi, Dunst, and the Ringed City color palette (ember gold on ash)
- **Full-disk encryption** — LUKS2 + Argon2id, unlocked at boot via GRUB
- **Triple-kernel architecture** — linux, linux-lts, linux-zen with Ringed City boot profiles
- **Pre-boot security** — AppArmor, audit, sysctl hardening, UFW, fail2ban configured before first login
- **Btrfs** — 7 subvolumes, zstd compression, snapshots, copies=2 on archival data
- **Local LLM** — Animus + Ollama with configurable models, no cloud dependency (Users choice between niche and highly compatible tool)
- **Offline knowledge** — Kiwix (Wikipedia, Arch Wiki, Stack Overflow)
- **Template-based theming** — switch between Ringed City, Catppuccin Mocha, or Dracula with one config line

---

## Hardware Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | x86_64 with UEFI | Any modern 64-bit CPU |
| Storage | 120 GB | 512 GB+ (NVMe preferred) |
| RAM | 4 GB | 16 GB+ (for local LLM) |
| Network | Required for install | Ethernet simplest |
| Boot mode | **UEFI only** | Secure Boot supported |

---

## Build Guide: Step by Step

This walks you through a complete LogOS install on bare metal or VM from a USB flash drive. Every step has an explicit command to run and an explanation of why.

### 1. Prepare the USB with Ventoy

[Ventoy](https://www.ventoy.net/) is a tool that makes a USB bootable and lets you drop ISO files onto it like a normal drive — no disk imaging, no risk of overwriting the wrong disk. Install it on your USB from another PC first.

**On Windows:** Download `ventoy-x.x.x-windows.zip` from [ventoy.net](https://www.ventoy.net/en/download.html), extract, run `Ventoy2Disk.exe`, select your USB, click Install.

**On Linux:** Download the tarball, extract, run `sudo bash VentoyWeb.sh`, open the browser URL, select your USB, click Install.

After Ventoy is installed, the USB shows up as a normal drive. Copy the Artix ISO onto it:

1. Download the [latest Artix ISO (OpenRC base)](https://artixlinux.org/download.php)
   - Choose the **base** OpenRC ISO (not the desktop editions)
2. Verify it (a compromised installer is game over before you start):
   ```bash
   # Artix provides SHA256 checksums on the download page
   sha256sum artix-base-openrc-*.iso
   # Compare with the hash shown on artixlinux.org
   ```
   If the checksum doesn't match, **do not proceed**. Re-download.
3. Copy `artix-base-openrc-*.iso` to the USB (drag and drop or `cp`)

That's it. The USB is now bootable.

### 2. Get the Repo into the Live Environment

You need the LogOS repo accessible from the Artix live session. Pick one:

**Option A — Git clone after boot (recommended)**
Network is already required for `basestrap`, so cloning costs nothing extra:
```bash
# After booting the Artix ISO and connecting to network:
pacman -Sy --noconfirm git
git clone https://github.com/crussella0129/LogOS-Artix.git
```

**Option B — Second USB**
Clone the repo onto a second USB from your current machine. After booting the Artix ISO, plug it in and mount:
```bash
lsblk                          # find the second USB (e.g., /dev/sdc1)
mkdir /mnt/repo
mount /dev/sdc1 /mnt/repo      # adjust device as needed
cp -r /mnt/repo/LogOS-Artix .
umount /mnt/repo
```

**Option C — Ventoy USB with reserved partition (offline, everything on one stick)**
During Ventoy installation, reserve space for a third partition (`-r SIZE_MB` on Linux, or the "Partition Style" option in the GUI). Format that partition as ext4, and copy the repo onto it from your current machine. After booting, the reserved partition is mountable (it's not the ISO partition, so it won't be busy):
```bash
lsblk                          # find the third partition (e.g., /dev/sda3)
mkdir /mnt/repo
mount /dev/sda3 /mnt/repo
cp -r /mnt/repo/LogOS-Artix .
umount /mnt/repo
```

### 3. Configure `logos.conf`

```bash
cd LogOS-Artix
cp logos.conf.example logos.conf
nano logos.conf    # or vim, whatever is available
```

**Must set before running anything:**

| Variable | What to set | How to find it |
|----------|-------------|----------------|
| `LOGOS_DISK` | Target disk (e.g., `/dev/nvme0n1`, `/dev/sda`) | `lsblk` — NVMe drives show as `nvme0n1`, SATA as `sda` |
| `LOGOS_HOSTNAME` | Machine name (e.g., `logos`, `citadel`) | Your choice — alphanumeric, no spaces |
| `LOGOS_USERNAME` | Your login username (e.g., `ashen`) | Your choice — lowercase, no spaces |
| `LOGOS_TIMEZONE` | Timezone (e.g., `America/New_York`) | `timedatectl list-timezones \| grep America` |

**Desktop and theme (optional, defaults shown):**

| Variable | Default | Options |
|----------|---------|---------|
| `LOGOS_DESKTOP` | `hyprland` | `hyprland`, `kde`, `sway`, `i3` |
| `LOGOS_THEME` | `ringed-city` | `ringed-city`, `catppuccin-mocha`, `dracula` |
| `LOGOS_TERMINAL` | *(auto)* | `kitty`, `alacritty` (empty = desktop default) |

**Package toggles (1=install, 0=skip):**

| Variable | Default | Packages |
|----------|---------|----------|
| `LOGOS_PKG_OFFICE` | 1 | LibreOffice, Thunderbird, Firefox, Chromium |
| `LOGOS_PKG_DEV` | 1 | VS Code, Git, Python, Node.js, Docker |
| `LOGOS_PKG_SECURITY` | 0 | Wireshark, nmap, hashcat, Metasploit (AUR) |
| `LOGOS_PKG_RADIO` | 0 | GQRX, GNU Radio, Direwolf, SDRangel (AUR) |
| `LOGOS_PKG_GAMING` | 0 | Steam, Lutris, Wine, MangoHud |
| `LOGOS_PKG_MEDIA` | 1 | VLC, mpv, OBS, GIMP, Inkscape, Audacity |
| `LOGOS_PKG_ENGINEERING` | 0 | FreeCAD, KiCad, Blender, Fusion 360 (AUR) |

**All other settings** (LUKS cipher, Btrfs mount options, kernel profiles, security toggles) have sane defaults. Review `logos.conf.example` for the full list.

### 4. Boot the Artix ISO

Boot your target machine from the USB. Select the **Artix Linux** boot entry.

If on WiFi:
```bash
iwctl
# device list                     ← find your wireless device name
# station wlan0 scan
# station wlan0 get-networks
# station wlan0 connect "YourNetworkName"
# exit
```

### 5. Verify the Live Environment

Before touching any disk, verify that the live environment is ready.

**What this checks and why:**
- **UEFI mode** — LogOS requires UEFI for Secure Boot compatibility and the GPT partition scheme. Legacy BIOS is not supported.
- **Network** — Required for downloading packages via `basestrap`. Wired is simplest; wireless uses `iwctl`.
- **Clock sync** — Incorrect time causes GPG signature verification failures during package installation.
- **Pacman keyring** — Stale keyrings cause package installation failures. The script refreshes keys and optionally optimizes mirrors.

```bash
cd LogOS-Artix
bash scripts/00-verify-env.sh
```

This checks all of the above, refreshes the keyring, optionally optimizes mirrors (if `LOGOS_MIRROR_COUNTRY` is set in `logos.conf`), and displays your configuration summary for review.

### 6. Disk Setup

This is the most critical and **destructive** step. Everything on the target disk will be erased.

#### Partition Scheme

LogOS uses a three-partition GPT layout:

| Partition | Size | Type | Filesystem | Mount |
|-----------|------|------|------------|-------|
| EFI | 1 GB | EF00 | FAT32 | `/boot/efi` |
| Boot | 4 GB | 8300 | ext4 | `/boot` |
| Root | Remainder | 8309 | LUKS2 → Btrfs | `/` |

**Why a separate EFI partition?** GRUB's EFI stub lives here. Keeping it separate from `/boot` means the EFI System Partition only holds the bootloader, not kernel images — which matters for Secure Boot signing.

**Why 4 GB for `/boot`?** The triple-kernel architecture generates six initramfs images (3 kernels × 2 initramfs each). Running out of `/boot` space during kernel updates is a common failure mode on Arch.

#### LUKS2 Encryption

LogOS uses LUKS2 with Argon2id as the key derivation function. Argon2id is resistant to both GPU-based and side-channel attacks, making it superior to PBKDF2 for passphrase-derived keys.

| Parameter | Default | Why |
|-----------|---------|-----|
| `LOGOS_LUKS_CIPHER` | `aes-xts-plain64` | Industry standard, hardware-accelerated on modern CPUs |
| `LOGOS_LUKS_KEY_SIZE` | `512` | 512-bit XTS = two 256-bit AES keys (one for encryption, one for tweak) |
| `LOGOS_LUKS_HASH` | `sha512` | Used for master key digest |
| `LOGOS_LUKS_PBKDF` | `argon2id` | Memory-hard KDF — resists GPU/ASIC brute-force and side-channel attacks |

These defaults are strong. Change them only if you have a specific reason.

#### Btrfs Subvolume Layout

| Subvolume | Mount Point | Purpose |
|-----------|-------------|---------|
| `@` | `/` | Root filesystem |
| `@home` | `/home` | User data |
| `@canon` | `/srv/cold-canon` | Cold Canon archival (copies=2 for bitrot protection) |
| `@mesh` | `/srv/warm-mesh` | Warm Mesh sync workspace |
| `@snapshots` | `/.snapshots` | Snapper snapshots |
| `@log` | `/var/log` | Logs (nodatacow for write performance) |
| `@pkg` | `/var/cache/pacman/pkg` | Package cache |

**Why separate subvolumes?** Each subvolume can have independent snapshot policies, mount options, and backup schedules. `@log` uses `nodatacow` because log files are write-heavy and don't benefit from copy-on-write. `@canon` uses `copies=2` so Btrfs stores two copies of each extent, providing protection against silent data corruption on archival data. `@pkg` is separated so package cache churn doesn't inflate snapshots.

#### Run the script

```bash
# ⚠ THIS DESTROYS ALL DATA ON LOGOS_DISK
bash scripts/01-disk-setup.sh
```

The script partitions the disk with `sgdisk`, formats LUKS2 (you'll be prompted for a passphrase), creates Btrfs with all seven subvolumes, and mounts everything at `/mnt`.

### 7. Base Install

With filesystems mounted, install the minimum packages needed to boot.

#### Package Tiers

LogOS uses a tiered installation strategy that minimizes the debugging surface if something goes wrong:

**Tier 0 (Boot-Critical)** — Only packages required to reach a login prompt. If Tier 0 fails, debugging is trivial because the surface area is tiny.

- `base`, `linux`, `linux-firmware`, `linux-headers` — kernel and core system
- `linux-lts`, `linux-zen` — additional kernels for Ringed City profiles
- `grub`, `efibootmgr` — bootloader
- CPU microcode (`intel-ucode` or `amd-ucode`) — auto-detected via `lscpu`
- `btrfs-progs`, `cryptsetup` — filesystem and encryption tools
- `networkmanager` — post-boot connectivity
- `sudo`, `nano`, `man-db`, `man-pages` — bare essentials

**Tier 1 (Security Infrastructure)** — Installed immediately after Tier 0 because security should be configured *before* first boot, not bolted on after.

- `apparmor`, `audit` — mandatory access control + audit logging
- `ufw` — firewall
- `openssh` — remote access (disabled by default)
- `fail2ban` (optional) — brute-force protection

#### Run the script

```bash
bash scripts/02-base-install.sh
```

This runs `basestrap` for Tier 0, installs Tier 1 via `artix-chroot`, generates fstab with `fstabgen`, and copies the LogOS configuration into the new system at `/root/LogOS/`.

### 8. Enter Chroot

Now enter the new system to configure it before first boot:

```bash
artix-chroot /mnt
```

### 9. Chroot Configuration

Inside the chroot, set the system identity (timezone, locale, hostname, users) and build the initramfs.

#### mkinitcpio Hook Ordering

The hook order in `mkinitcpio.conf` is critical — get it wrong and you can't unlock your disk at boot:

```
HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt btrfs filesystems fsck)
```

**Why this order matters:**

| Rule | Reason |
|------|--------|
| `keyboard` + `keymap` **before** `encrypt` | You need to type your LUKS passphrase — keyboard drivers must be loaded first |
| `encrypt` **before** `filesystems` | The LUKS container must be opened before Btrfs can mount the root filesystem |
| `btrfs` **before** `filesystems` | Enables Btrfs multi-device support so the subvolumes can be found |
| `microcode` placed early | CPU errata fixes should be applied as early as possible during boot |
| `kms` **before** `block` | Ensures GPU driver is loaded early for proper display during disk unlock |

#### Run the script

```bash
bash /root/LogOS/03-chroot-setup.sh
# → You will be prompted to set root and user passwords
```

This configures timezone, locale, keymap, hostname, creates your user, writes `mkinitcpio.conf` with the correct hook ordering, and runs `mkinitcpio -P` to generate initramfs for all installed kernels.

### 10. Bootloader

GRUB is the bootloader, configured with LUKS2 encryption support and the Ringed City boot profiles.

#### Ringed City Profiles

The three profiles are named after bosses from Dark Souls 3's *The Ringed City* DLC — each representing a different balance of defense and aggression:

| Profile | Kernel | Security | Use Case | Perf. Impact |
|---------|--------|----------|----------|-------------|
| **Gael** | linux-lts | Maximum — lockdown, no SMT, full LSM, init_on_alloc/free | Hostile environments, border crossings | ~15-30% |
| **Midir** | linux-zen | Balanced — auto mitigations, AppArmor, audit | Daily driver, general use | ~2-5% |
| **Halflight** | linux-zen | Minimal — mitigations off, no audit | Gaming, media production, HPC | None |

**Gael** (Slave Knight Gael) represents ultimate resilience through adversity. He uses `linux-lts` for maximum stability, `lockdown=confidentiality` to prevent runtime kernel modification, and `nosmt=force` to disable hyper-threading (Spectre mitigation).

**Midir** (Darkeater Midir) balances power with calculated risk. `linux-zen` provides better scheduling and interactivity for desktop use, while `mitigations=auto` applies the kernel's recommended security patches.

**Halflight** (Spear of the Church) prioritizes speed. `mitigations=off` removes all CPU vulnerability mitigations for maximum performance. Use only in trusted environments where the threat model permits it.

#### Kernel Parameters Deep-Dive

| Parameter | Gael | Midir | Halflight | Purpose |
|-----------|------|-------|-----------|---------|
| `cryptdevice=UUID=...:cryptroot` | ✓ | ✓ | ✓ | LUKS unlock at boot |
| `apparmor=1` | ✓ | ✓ | — | Enable AppArmor LSM |
| `audit=1` | ✓ | ✓ | — | Enable audit subsystem |
| `lsm=...` | ✓ | ✓ | — | LSM stack ordering |
| `lockdown=confidentiality` | ✓ | — | — | Prevent runtime kernel modification |
| `mitigations=auto,nosmt` | ✓ | — | — | All CPU mitigations + SMT off |
| `mitigations=auto` | — | ✓ | — | Recommended mitigations only |
| `mitigations=off` | — | — | ✓ | No mitigations (max performance) |
| `init_on_alloc=1 init_on_free=1` | ✓ | — | — | Zero memory on alloc/free |
| `slab_nomerge` | ✓ | — | — | Prevent slab merging (hardening) |

#### Run the script

```bash
bash /root/LogOS/04-bootloader.sh
```

This writes GRUB defaults, installs GRUB to the EFI partition, creates the `41_logos_profiles` custom GRUB script with baked-in UUIDs for your disk, disables the default `10_linux` generator, and runs `grub-mkconfig`.

### 11. Security Hardening

Security in LogOS is configured *before* first boot — it's not an afterthought bolted on later. This is a deliberate design choice: every layer is active from the first login.

#### Defense in Depth

LogOS implements multiple overlapping security layers. Each layer addresses a different attack vector, so a failure in one doesn't compromise the system:

| Layer | Mechanism | Protects Against |
|-------|-----------|-----------------|
| 1 | **LUKS2 disk encryption** | Data theft from powered-off device |
| 2 | **Kernel hardening** (sysctl) | Information leaks, privilege escalation |
| 3 | **AppArmor** | Per-application mandatory access control |
| 4 | **Audit** | Post-incident forensics, compliance logging |
| 5 | **UFW** | Unauthorized network access (default deny incoming) |
| 6 | **fail2ban** | Brute-force login attempts |
| 7 | **SSH hardening** | Remote access attack surface |

#### Sysctl Hardening

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

#### SSH Hardening

When `LOGOS_SSHD=1` in `logos.conf`, the SSH daemon is configured with:

- `PermitRootLogin no` — root cannot SSH in
- `PasswordAuthentication no` — keys only (no brute-force surface)
- `MaxAuthTries 3` — lock out after 3 failed attempts
- `ClientAliveInterval 300` — disconnect idle sessions after 5 minutes

#### Run the script

```bash
bash /root/LogOS/05-security.sh

exit  # leave chroot
```

This writes sysctl hardening, configures AppArmor + audit rules, sets up UFW (default deny incoming), and optionally configures fail2ban and SSH hardening based on your `logos.conf` settings.

### 12. First Boot

Everything before this point happens in the live environment or chroot. Now it's time to reboot into your LogOS system.

```bash
umount -R /mnt
reboot
# Remove USB when prompted
```

#### GRUB Menu

On reboot, GRUB presents the Ringed City profiles:

```
LogOS - Gael [Maximum Security]
LogOS - Midir [Daily Driver]
LogOS - Halflight [Performance]
LogOS Recovery Options ►
```

Select **Midir** for first boot (balanced default).

#### LUKS Unlock

You'll be prompted for your LUKS passphrase at two stages:

1. **GRUB stage** — GRUB unlocks the encrypted partition to find kernel images. This may appear slow — GRUB's cryptographic implementation is unoptimized. This is normal.
2. **initramfs stage** — The `encrypt` hook unlocks the partition again for the actual root mount. This is fast.

After unlocking, you should reach a login prompt. Log in with the username and password you set in step 9.

### 13. Desktop

After the first successful boot, install the desktop environment and apply the color theme.

#### Why Hyprland as Default?

Hyprland is a dynamic Wayland compositor with smooth animations, per-monitor workspaces, and a modern feature set. It represents the "cyberdeck superfluid" philosophy — fast, keyboard-driven, visually distinctive. If you need maximum stability or X11 compatibility, choose Sway or i3.

| Desktop | Type | Login Manager | Default Terminal | Use Case |
|---------|------|---------------|-----------------|----------|
| **Hyprland** (default) | Wayland compositor | greetd + tuigreet | kitty | Cyberdeck experience — tiling, animations, modern Wayland |
| **KDE Plasma** | Full desktop | SDDM | kitty | Traditional full-featured desktop with GUI tools |
| **Sway** | Wayland compositor | greetd + tuigreet | alacritty | i3-compatible Wayland — minimal, stable, proven |
| **i3** | X11 tiling WM | LightDM | alacritty | Classic X11 tiling — maximum compatibility |

#### Desktop Stack

All desktops share a common foundation:

**Shared packages:**
- **Audio:** Pipewire + ALSA/Pulse/JACK bridges + Wireplumber
- **Fonts:** Noto (CJK + emoji), Liberation, DejaVu, Fira Code, JetBrains Mono
- **Utilities:** xdg-user-dirs, xdg-utils
- **GPU drivers:** Auto-detected (see below)

**Shared dotfiles:** Terminal config (kitty and/or alacritty), Starship prompt, GTK 3/4 settings (dark theme, cursor, icon theme).

#### GPU Detection

The script auto-detects your GPU(s) via `lspci` and installs appropriate drivers:

| GPU | Packages | Notes |
|-----|----------|-------|
| NVIDIA | `nvidia nvidia-utils nvidia-settings nvidia-lts` | Proprietary; Wayland env vars auto-configured |
| AMD | `mesa vulkan-radeon libva-mesa-driver` | Open-source, recommended for Wayland |
| Intel | `mesa vulkan-intel intel-media-driver` | Open-source, integrated GPUs |

For NVIDIA on Wayland (Hyprland/Sway), the script writes environment variables to `/etc/environment.d/logos-nvidia.conf` to enable hardware acceleration and fix cursor rendering.

#### Run the script

```bash
cd /root/LogOS
sudo bash 06-desktop.sh
```

This loads the selected theme palette, installs shared packages (Pipewire, fonts, GPU drivers), installs desktop-specific packages and login manager, deploys themed dotfiles to `~/.config/`, and enables the login manager service.

### 14. Package Modules

LogOS organizes optional software into seven categories, each controlled by a `LOGOS_PKG_*` toggle in `logos.conf`:

| Category | Toggle | Key Packages |
|----------|--------|-------------|
| **Office** | `LOGOS_PKG_OFFICE` | LibreOffice, Thunderbird, Firefox, Chromium, Obsidian, Zotero |
| **Development** | `LOGOS_PKG_DEV` | VS Code, Git, Python, Node.js, Docker |
| **Security** | `LOGOS_PKG_SECURITY` | Wireshark, nmap, hashcat, Metasploit (AUR), Burp Suite (AUR) |
| **Radio/SAR** | `LOGOS_PKG_RADIO` | GQRX, GNU Radio, Direwolf, Xastir, SDRangel (AUR) |
| **Gaming** | `LOGOS_PKG_GAMING` | Steam, Lutris, Wine, MangoHud |
| **Media** | `LOGOS_PKG_MEDIA` | VLC, mpv, OBS, Kdenlive, GIMP, Inkscape, Audacity |
| **Engineering** | `LOGOS_PKG_ENGINEERING` | FreeCAD, OpenSCAD, KiCad, Blender, Fusion 360 (AUR) |

#### AUR Trust Model

Some packages (Metasploit, Burp Suite, Fusion 360, SDRangel, CHIRP) come from the Arch User Repository. AUR packages are:

- **Not officially supported** by Arch Linux
- **Built from source** on your machine (via `makepkg`)
- **Community-maintained** — review PKGBUILDs before installing

The script uses `yay` as the AUR helper, installed automatically when needed. AUR operations run as your unprivileged user (never root).

#### Run the script

```bash
sudo bash 07-packages.sh
```

### 15. Knowledge Infrastructure

The knowledge layer is what makes LogOS more than just another Arch install. It implements a three-tier information topology designed for resilience.

#### Cold / Warm / Hot Topology

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

#### Ollama (Local LLM)

When `LOGOS_OLLAMA=1` in `logos.conf`, the script installs [Ollama](https://ollama.com/) and pulls the models specified in `LOGOS_OLLAMA_MODELS`. Default models:

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

#### Kiwix (Offline Documentation)

[Kiwix](https://kiwix.org/) provides offline access to Wikipedia, Stack Overflow, Arch Wiki, and other knowledge bases via compressed ZIM files. Essential for operation without internet.

#### Run the script

```bash
sudo bash 08-knowledge.sh
```

### 16. Validation & First Desktop Login

#### Post-Build Validation

The validation script runs read-only checks across every major subsystem:

- **Boot:** UEFI mode, GRUB installed, all three kernels present
- **Encryption:** LUKS active, `cryptdevice` in kernel command line
- **Filesystem:** All 7 subvolumes mounted, zstd compression enabled, no Btrfs errors
- **Security:** AppArmor enforcing, audit running, UFW active, kernel hardening applied
- **Network:** NetworkManager active, firewall enabled
- **Snapshots:** Snapper configured and running
- **Knowledge:** Directory structure, Ollama service, branding files

```bash
sudo bash 09-validate.sh
```

A clean build should show all passes with possible warnings for optional features (like Snapper, which requires manual configuration — see below).

#### Snapper Setup (After Validation)

Configure automatic Btrfs snapshots:

```bash
# Install snapshot tools
sudo pacman -S --needed snapper snap-pac grub-btrfs

# Create root configuration
sudo snapper -c root create-config /

# Enable automatic snapshots (OpenRC)
# Snapper on OpenRC uses cron instead of systemd timers.
# Install cronie and add snapper jobs:
sudo rc-update add cronie default
sudo rc-service cronie start
# Add to /etc/cron.d/snapper:
#   */15 * * * * root snapper -c root create --cleanup-algorithm timeline
sudo rc-update add grub-btrfsd default 2>/dev/null || true
```

#### Reboot and Log In

Reboot one more time to reach the desktop login:

```bash
reboot
```

| Desktop | What you'll see | Login action |
|---------|----------------|-------------|
| **Hyprland** | tuigreet TUI | Select your user, type password |
| **KDE** | SDDM graphical | Click user, type password |
| **Sway** | tuigreet TUI | Select your user, type password |
| **i3** | LightDM graphical | Click user, type password |

**Hyprland keybindings to get started:**

| Key | Action |
|-----|--------|
| `Super + Return` | Terminal (kitty) |
| `Super + D` | App launcher (Rofi) |
| `Super + Q` | Close window |
| `Super + 1-0` | Switch workspace |
| `Super + Shift + 1-0` | Move window to workspace |
| `Super + F` | Fullscreen |
| `Super + V` | Toggle floating |
| `Super + Shift + E` | Exit Hyprland |
| `Print` | Screenshot (region) |
| `Super + Shift + L` | Lock screen |

---

## Color Themes

All three themes are applied at install time across every dotfile (terminal, bar, launcher, notifications, lock screen, GTK). Themes use template substitution — dotfiles contain placeholders that are replaced with the selected palette's colors during `06-desktop.sh`.

| Theme | Aesthetic | Background | Accent |
|-------|-----------|-----------|--------|
| **Ringed City** | Ash + ember gold (Dark Souls) | `#1a1714` | `#c78f40` |
| **Catppuccin Mocha** | Warm pastels | `#1e1e2e` | `#cba6f7` |
| **Dracula** | Classic dark | `#282a36` | `#bd93f9` |

To switch themes after install, edit `LOGOS_THEME` in `logos.conf` and re-run `06-desktop.sh`.

---

## Desktop Stacks

| | Hyprland (default) | KDE Plasma | Sway | i3 |
|-|-------------------|------------|------|-----|
| **Type** | Wayland compositor | Full DE | Wayland compositor | X11 tiling WM |
| **Bar** | Waybar | KDE panel | Waybar | Polybar |
| **Launcher** | Rofi (Wayland) | KRunner | Rofi (Wayland) | Rofi / dmenu |
| **Notifications** | Dunst | KDE | Mako | Dunst |
| **Terminal** | kitty | kitty | alacritty | alacritty |
| **Login** | greetd + tuigreet | SDDM | greetd + tuigreet | LightDM |
| **Lock** | hyprlock | KDE | swaylock | — |

Shared across all desktops: Pipewire audio, auto-detected GPU drivers, Noto/Fira Code/JetBrains Mono fonts, Starship prompt, GTK dark theme.

---

## VM Quick Test

If you want to test without touching hardware:

```bash
# Create disk image
qemu-img create -f qcow2 logos-test.qcow2 120G

# Boot with Artix ISO
qemu-system-x86_64 \
  -enable-kvm \
  -m 8192 \
  -cpu host \
  -smp 4 \
  -drive file=logos-test.qcow2,format=qcow2 \
  -cdrom artix-base-openrc-x86_64.iso \
  -boot d \
  -bios /usr/share/ovmf/OVMF.fd \
  -vga virtio \
  -device virtio-net-pci,netdev=net0 \
  -netdev user,id=net0
```

VirtualBox/VMware: Create VM with 8 GB RAM, 120 GB disk, **UEFI firmware enabled**, attach the Artix ISO.

---

## Repository Structure

```
LogOS-Artix/
├── docs/
│   └── appendices/
│       ├── threat-model.md         # Threat model + security boundaries
│       ├── hardware-compat.md      # Verified hardware + GPU matrix
│       └── troubleshooting.md      # Recovery procedures
├── scripts/
│   ├── 00-verify-env.sh            # Live env checks
│   ├── 01-disk-setup.sh            # Partition + LUKS + Btrfs
│   ├── 02-base-install.sh          # basestrap + fstab
│   ├── 03-chroot-setup.sh          # System identity + initramfs
│   ├── 04-bootloader.sh            # GRUB + Ringed City profiles
│   ├── 05-security.sh              # Kernel hardening, firewall, SSH
│   ├── 06-desktop.sh               # Desktop dispatcher (multi-DE)
│   ├── 07-packages.sh              # Optional package categories
│   ├── 08-knowledge.sh             # Cold Canon + Ollama + Kiwix
│   └── 09-validate.sh              # Post-build validation
├── lib/
│   ├── common.sh                   # Logging, config, package helpers
│   ├── detect.sh                   # Hardware detection (CPU, GPU, disk)
│   ├── desktop.sh                  # Theme engine, dotfile deployment
│   ├── desktop-hyprland.sh         # Hyprland module
│   ├── desktop-kde.sh              # KDE Plasma module
│   ├── desktop-sway.sh             # Sway module
│   └── desktop-i3.sh               # i3 module
├── dotfiles/
│   ├── themes/                     # ringed-city.sh, catppuccin-mocha.sh, dracula.sh
│   ├── hyprland/                   # hypr/, waybar/, rofi/, dunst/
│   ├── sway/                       # sway/, waybar/, mako/
│   └── shared/                     # kitty/, alacritty/, starship, GTK
├── logos.conf.example              # Configuration template
└── LICENSE
```

---

## Script Reference

| # | Script | What it does | Runs on |
|---|--------|-------------|---------|
| 00 | `verify-env.sh` | UEFI, network, clock, keyring, mirrors | Live USB |
| 01 | `disk-setup.sh` | Partition, LUKS2, Btrfs subvolumes | Live USB |
| 02 | `base-install.sh` | basestrap Tier 0+1, fstab, copy LogOS to system | Live USB |
| 03 | `chroot-setup.sh` | Timezone, locale, user, mkinitcpio | artix-chroot |
| 04 | `bootloader.sh` | GRUB + Ringed City boot profiles | artix-chroot |
| 05 | `security.sh` | sysctl, AppArmor, UFW, fail2ban, SSH | artix-chroot |
| 06 | `desktop.sh` | Desktop + theme + GPU + Pipewire + fonts | Booted system |
| 07 | `packages.sh` | 7 optional package categories | Booted system |
| 08 | `knowledge.sh` | Cold Canon, Ollama, Kiwix, branding | Booted system |
| 09 | `validate.sh` | Read-only validation of all subsystems | Booted system |

---

## Recovery

If something goes wrong, boot from the Artix ISO and follow these steps:

```bash
# 1. Find your encrypted partition
lsblk
# Look for the partition layout you created:
#   NVMe: /dev/nvme0n1p3  (third partition)
#   SATA: /dev/sda3        (third partition)
# The root partition is always the third (after EFI and boot).

# 2. Open encrypted volume (use your actual partition, e.g., /dev/nvme0n1p3)
cryptsetup open /dev/nvme0n1p3 cryptroot

# 3. Mount root subvolume
mount -o subvol=@ /dev/mapper/cryptroot /mnt

# 4. Mount boot partitions (use your actual disk)
#    Find them with: lsblk — they're partitions 1 (EFI) and 2 (boot)
mount /dev/nvme0n1p2 /mnt/boot
mount /dev/nvme0n1p1 /mnt/boot/efi

# 5. Chroot in
artix-chroot /mnt

# 6. Fix the problem, for example:
#    Regenerate initramfs:  mkinitcpio -P
#    Reinstall GRUB:        grub-install --target=x86_64-efi --efi-directory=/boot/efi
#    Rebuild GRUB config:   grub-mkconfig -o /boot/grub/grub.cfg

# 7. Exit, unmount, reboot
exit
umount -R /mnt
reboot
```

For detailed recovery procedures (GRUB rescue, encrypt hook failures, kernel panic, Btrfs corruption, snapshot rollback), see [Troubleshooting](docs/appendices/troubleshooting.md).

---

## Troubleshooting

**Can't boot the USB?** Check UEFI is enabled in BIOS/firmware. Disable Secure Boot if the ISO won't load.

**No network in live env?** Wired is plug-and-play. For WiFi, use `iwctl`. The verify script will tell you if it can't reach the network.

**LUKS passphrase prompt is slow at GRUB?** Normal. GRUB's crypto implementation is unoptimized. The second prompt (initramfs) is fast.

**Wrong disk in `logos.conf`?** Run `lsblk` to see all disks. NVMe drives are `/dev/nvme0n1`, SATA drives are `/dev/sda`.

**Script fails mid-run?** Every script is re-runnable. Fix the issue and run it again. For chroot recovery, see [Troubleshooting](docs/appendices/troubleshooting.md).

**Hyprland won't start on NVIDIA?** The installer auto-configures NVIDIA Wayland env vars. If it still fails, check `/etc/environment.d/logos-nvidia.conf` exists. Fallback: set `LOGOS_DESKTOP=sway` or `LOGOS_DESKTOP=kde`.

---

## Sovereign Compute

LogOS is built for a world where software availability, distribution infrastructure, and upstream governance cannot be taken for granted. The following provisions ensure LogOS can sustain itself.

### What to Cache Now

While these resources are still freely available, acquire and store them in Cold Canon (`/srv/cold-canon/software/`):

| Resource | Why | How |
|----------|-----|-----|
| **Artix ISO + repo snapshot** | Rebuild from scratch if mirrors disappear | `rsync` a mirror or use `pacman -Sw` to download without installing |
| **Arch package cache** | Artix shares Arch repos; cache critical packages | Keep `/var/cache/pacman/pkg/` (@pkg subvol) populated |
| **GCC/binutils/make source tarballs** | Bootstrap a compiler toolchain from source | Download from GNU FTP mirrors |
| **Linux kernel source** | Build custom kernels without network | `git clone --bare` kernel.org |
| **Kiwix ZIM files** | Wikipedia, Arch Wiki, Stack Overflow offline | Download from kiwix.org/library |
| **Ollama model weights** | Local LLM with no cloud dependency | `ollama pull` caches in `~/.ollama/models/` |
| **Rustup + Cargo registry** | Build Rust tools (ripgrep, fd, bat, etc.) | `rustup` offline installer + `cargo vendor` |
| **Python + pip wheels** | Critical Python tools | `pip download` to a local directory |

### Self-Hosting Verification

After installation, verify the system can rebuild itself:

```bash
# Verify compiler toolchain
gcc --version && g++ --version && make --version

# Verify package manager works offline (with cached packages)
pacman -S --noconfirm --needed base-devel  # should resolve from cache

# Verify kernel can be rebuilt
ls /usr/src/linux-*/  # kernel source should be present

# Verify Btrfs tools for filesystem maintenance
btrfs --version && btrfs scrub start -Bd /
```

### Package Cache Strategy

The `@pkg` Btrfs subvolume at `/var/cache/pacman/pkg/` is kept separate so it persists across system snapshots. To pre-populate it for offline use:

```bash
# Download all currently-installed packages (without reinstalling)
pacman -Sw $(pacman -Qqe)

# Download a broader set of common packages
pacman -Sw base-devel linux linux-headers linux-lts linux-zen \
  grub efibootmgr btrfs-progs cryptsetup networkmanager \
  gcc make cmake meson autoconf automake \
  python python-pip nodejs npm git
```

### Replication Guide

To clone the entire LogOS environment to another machine:

1. Create an Artix live USB
2. Copy the LogOS repo + `logos.conf` to the USB
3. Copy `/var/cache/pacman/pkg/` to the USB (for offline install)
4. Copy Cold Canon (`/srv/cold-canon/`) to the USB
5. On the target machine, run the scripts from 00-09
6. Restore Cold Canon content

---

## Appendices

- [Threat Model & Security Architecture](docs/appendices/threat-model.md) — Formal threat table, security boundaries, profile selection guide
- [Hardware Compatibility](docs/appendices/hardware-compat.md) — Verified hardware, GPU decision matrix, known issues
- [Troubleshooting](docs/appendices/troubleshooting.md) — Failure modes, recovery procedures, emergency quick reference
