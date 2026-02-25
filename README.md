# LogOS — Ontology Substrate Operating System

**Version:** 2025.8 (Ringed City)
**Base:** Arch Linux | **Arch:** x86_64 | **License:** GPLv3

> *"A civilization does not collapse when it loses data. It collapses when it loses procedural knowledge."*

LogOS is a hardened, encrypted, offline-capable Arch Linux system with Animus local LLM inference (<https://github.com/crussella0129/Animus>) and a three-tier knowledge preservation topology that includes the GitGael Surviavl Repo (<https://github.com/crussella0129/GitGael>). It ships with a cyberdeck-first desktop (Hyprland) with a theme and color scheme fitting the end of the world (from Dark Souls 3 at least).

---

## What You Get

- **Hyprland cyberdeck desktop** with Waybar, Rofi, Dunst, and the Ringed City color palette (ember gold on ash)
- **Full-disk encryption** — LUKS2 + Argon2id, unlocked at boot via GRUB
- **Triple-kernel architecture** — linux, linux-lts, linux-zen with Ringed City boot profiles
- **Pre-boot security** — AppArmor, audit, sysctl hardening, UFW, fail2ban configured before first login
- **Btrfs** — 7 subvolumes, zstd compression, snapshots, copies=2 on archival data
- **Local LLM** — Ollama with configurable models, no cloud dependency
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

## Flash Drive Test: Step by Step

This walks you through a complete LogOS install on bare metal or VM from a USB flash drive.

### 1. Prepare the USB with Ventoy

[Ventoy](https://www.ventoy.net/) is a tool that makes a USB bootable and lets you drop ISO files onto it like a normal drive — no disk imaging, no risk of overwriting the wrong disk. Install it on your USB from another PC first.

**On Windows:** Download `ventoy-x.x.x-windows.zip` from [ventoy.net](https://www.ventoy.net/en/download.html), extract, run `Ventoy2Disk.exe`, select your USB, click Install.

**On Linux:** Download the tarball, extract, run `sudo bash VentoyWeb.sh`, open the browser URL, select your USB, click Install.

After Ventoy is installed, the USB shows up as a normal drive. Copy the Arch ISO onto it:

1. Download the [latest Arch ISO](https://archlinux.org/download/)
2. *(Optional)* Verify it:
   ```bash
   sha256sum -c sha256sums.txt --ignore-missing
   gpg --keyserver-options auto-key-retrieve --verify archlinux-x86_64.iso.sig
   ```
3. Copy `archlinux-x86_64.iso` to the USB (drag and drop or `cp`)

That's it. The USB is now bootable.

### 2. Get the Repo into the Live Environment

You need the LogOS-Arch repo accessible from the Arch live session. Pick one:

**Option A — Git clone after boot (recommended)**
Network is already required for `pacstrap`, so cloning costs nothing extra:
```bash
# After booting the Arch ISO and connecting to network:
pacman -Sy --noconfirm git
git clone https://github.com/crussella0129/LogOS-Arch.git
```

**Option B — Second USB**
Clone the repo onto a second USB from your current machine. After booting the Arch ISO, plug it in and mount:
```bash
lsblk                          # find the second USB (e.g., /dev/sdc1)
mkdir /mnt/repo
mount /dev/sdc1 /mnt/repo      # adjust device as needed
cp -r /mnt/repo/LogOS-Arch .
umount /mnt/repo
```

**Option C — Ventoy USB with reserved partition (offline, everything on one stick)**
During Ventoy installation, reserve space for a third partition (`-r SIZE_MB` on Linux, or the "Partition Style" option in the GUI). Format that partition as ext4, and copy the repo onto it from your current machine. After booting, the reserved partition is mountable (it's not the ISO partition, so it won't be busy):
```bash
lsblk                          # find the third partition (e.g., /dev/sda3)
mkdir /mnt/repo
mount /dev/sda3 /mnt/repo
cp -r /mnt/repo/LogOS-Arch .
umount /mnt/repo
```

### 3. Configure `logos.conf`

```bash
cd LogOS-Arch
cp logos.conf.example logos.conf
nano logos.conf    # or vim, whatever is available
```

**Must set before running anything:**

| Variable | What to set | How to find it |
|----------|-------------|----------------|
| `LOGOS_DISK` | Target disk (e.g., `/dev/nvme0n1`, `/dev/sda`) | `lsblk` |
| `LOGOS_HOSTNAME` | Machine name | Your choice |
| `LOGOS_USERNAME` | Your login username | Your choice |
| `LOGOS_TIMEZONE` | Timezone | `timedatectl list-timezones \| grep America` |

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

### 4. Boot the Arch ISO

Boot your target machine from the USB. Select **"Arch Linux install medium (x86_64, UEFI)"**.

If on WiFi:
```bash
iwctl
# station wlan0 scan
# station wlan0 get-networks
# station wlan0 connect "YourNetworkName"
# exit
```

### 5. Run the Build

The entire build is 10 scripts run in order. Each script validates its own prerequisites and will stop if something is wrong.

**Phase A — Live USB (scripts 00-02)**

```bash
cd LogOS-Arch

# Verify live environment (UEFI, network, clock, keyring)
bash scripts/00-verify-env.sh

# Partition, encrypt, create Btrfs subvolumes
# ⚠ THIS DESTROYS ALL DATA ON LOGOS_DISK
bash scripts/01-disk-setup.sh

# Install base packages, generate fstab, copy LogOS to new system
bash scripts/02-base-install.sh
```

**Phase B — Chroot (scripts 03-05)**

```bash
arch-chroot /mnt

# System identity: timezone, locale, user, mkinitcpio
bash /root/LogOS/03-chroot-setup.sh
# → You will be prompted to set root and user passwords

# GRUB bootloader with Ringed City profiles
bash /root/LogOS/04-bootloader.sh

# Security hardening: sysctl, AppArmor, UFW, fail2ban, SSH
bash /root/LogOS/05-security.sh

exit  # leave chroot
```

**Phase C — Reboot**

```bash
umount -R /mnt
reboot
# Remove USB when prompted
```

Select **Midir** (daily driver) at the GRUB menu. Enter your LUKS passphrase. Log in.

**Phase D — Booted System (scripts 06-09)**

```bash
cd /root/LogOS

# Desktop environment + theme + GPU drivers
sudo bash 06-desktop.sh

# Optional package categories
sudo bash 07-packages.sh

# Knowledge infrastructure (Cold Canon, Ollama, Kiwix)
sudo bash 08-knowledge.sh

# Validate everything
sudo bash 09-validate.sh
```

Reboot one more time to reach the desktop login.

### 6. First Desktop Login

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

## Ringed City Boot Profiles

Named after bosses from Dark Souls 3's *The Ringed City* DLC:

| Profile | Kernel | Security | Use Case | Perf. Impact |
|---------|--------|----------|----------|-------------|
| **Gael** | linux-lts | Maximum — lockdown, no SMT, full LSM, init_on_alloc/free | Hostile environments, border crossings | ~15-30% |
| **Midir** | linux-zen | Balanced — auto mitigations, AppArmor, audit | Daily driver, general use | ~2-5% |
| **Halflight** | linux-zen | Minimal — mitigations off, no audit | Gaming, media production, HPC | None |

---

## Color Themes

All three themes are applied at install time across every dotfile (terminal, bar, launcher, notifications, lock screen, GTK).

| Theme | Aesthetic | Background | Accent |
|-------|-----------|-----------|--------|
| **Ringed City** | Ash + ember gold (Dark Souls) | `#1a1714` | `#c78f40` |
| **Catppuccin Mocha** | Warm pastels | `#1e1e2e` | `#cba6f7` |
| **Dracula** | Classic dark | `#282a36` | `#bd93f9` |

To switch themes, edit `LOGOS_THEME` in `logos.conf` and re-run `06-desktop.sh`.

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

# Boot with Arch ISO
qemu-system-x86_64 \
  -enable-kvm \
  -m 8192 \
  -cpu host \
  -smp 4 \
  -drive file=logos-test.qcow2,format=qcow2 \
  -cdrom archlinux-x86_64.iso \
  -boot d \
  -bios /usr/share/ovmf/OVMF.fd \
  -vga virtio \
  -device virtio-net-pci,netdev=net0 \
  -netdev user,id=net0
```

VirtualBox/VMware: Create VM with 8 GB RAM, 120 GB disk, **UEFI firmware enabled**, attach the Arch ISO.

---

## Repository Structure

```
LogOS-Arch/
├── docs/
│   ├── build-guide.md              # Literate build guide (the full story)
│   └── appendices/
│       ├── threat-model.md         # Threat model + security boundaries
│       ├── hardware-compat.md      # Verified hardware + GPU matrix
│       └── troubleshooting.md      # Recovery procedures
├── scripts/
│   ├── 00-verify-env.sh            # Live env checks
│   ├── 01-disk-setup.sh            # Partition + LUKS + Btrfs
│   ├── 02-base-install.sh          # pacstrap + fstab
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
| 02 | `base-install.sh` | pacstrap Tier 0+1, fstab, copy LogOS to system | Live USB |
| 03 | `chroot-setup.sh` | Timezone, locale, user, mkinitcpio | arch-chroot |
| 04 | `bootloader.sh` | GRUB + Ringed City boot profiles | arch-chroot |
| 05 | `security.sh` | sysctl, AppArmor, UFW, fail2ban, SSH | arch-chroot |
| 06 | `desktop.sh` | Desktop + theme + GPU + Pipewire + fonts | Booted system |
| 07 | `packages.sh` | 7 optional package categories | Booted system |
| 08 | `knowledge.sh` | Cold Canon, Ollama, Kiwix, branding | Booted system |
| 09 | `validate.sh` | Read-only validation of all subsystems | Booted system |

---

## Troubleshooting

**Can't boot the USB?** Check UEFI is enabled in BIOS/firmware. Disable Secure Boot if the ISO won't load.

**No network in live env?** Wired is plug-and-play. For WiFi, use `iwctl`. The verify script will tell you if it can't reach the network.

**LUKS passphrase prompt is slow at GRUB?** Normal. GRUB's crypto implementation is unoptimized. The second prompt (initramfs) is fast.

**Wrong disk in `logos.conf`?** Run `lsblk` to see all disks. NVMe drives are `/dev/nvme0n1`, SATA drives are `/dev/sda`.

**Script fails mid-run?** Every script is re-runnable. Fix the issue and run it again. For chroot recovery, see [troubleshooting](docs/appendices/troubleshooting.md).

**Hyprland won't start on NVIDIA?** The installer auto-configures NVIDIA Wayland env vars. If it still fails, check `/etc/environment.d/logos-nvidia.conf` exists. Fallback: set `LOGOS_DESKTOP=sway` or `LOGOS_DESKTOP=kde`.

---

## Deep Dive

For the full rationale behind every design decision — why Argon2id over PBKDF2, why 7 subvolumes, why pre-boot security, how the Cold/Warm/Hot topology works — read the [Build Guide](docs/build-guide.md).

For threat modeling, security boundaries, and profile selection criteria, see [Threat Model](docs/appendices/threat-model.md).
