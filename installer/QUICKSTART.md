# LogOS Installer - Quick Start Guide

## TL;DR - Fastest Path to Installation

### 1. Boot Arch Linux Live USB

### 2. Connect to Internet

```bash
# Wired (auto)
dhcpcd

# Wireless
iwctl
# Then: station wlan0 connect "NetworkName"
```

### 3. Download and Run Installer

```bash
pacman -Sy git
git clone https://github.com/crussella0129/LogOS.git
cd LogOS/installer
chmod +x install-logos.sh
./install-logos.sh
```

### 4. Follow Prompts

You'll be asked for:
- Target disk
- Hostname
- Username
- Timezone
- LUKS passphrase (20+ chars)
- Passwords
- GPU type
- Desktop environment

### 5. Reboot

```bash
systemctl reboot
```

### 6. After First Boot (Optional)

Install desktop and applications:

```bash
cd LogOS/installer/modules
chmod +x tier2-standalone.sh
./tier2-standalone.sh
sudo reboot
```

Install specialized tools:

```bash
cd LogOS/installer/modules
chmod +x tier3-standalone.sh
./tier3-standalone.sh
```

## What Gets Installed

### Core System (Automatic)
- ✅ LUKS2 encrypted disk
- ✅ Btrfs filesystem with subvolumes
- ✅ Triple-kernel architecture (linux, linux-lts, linux-zen)
- ✅ GRUB with Ringed City boot profiles
- ✅ Security hardening (AppArmor, audit, UFW, fail2ban)
- ✅ Network configuration (NetworkManager)
- ✅ Base system tools

### Tier 2 - Desktop & Workstation (tier2-standalone.sh)
- ✅ Graphics drivers (AMD/NVIDIA/Intel)
- ✅ Desktop environment (GNOME/KDE/XFCE/i3)
- ✅ Essential apps (Firefox, LibreOffice, GIMP, etc.)
- ✅ Development tools (Git, Python, Node.js, Rust, Go, Docker, VS Code)
- ✅ Terminal enhancements (zsh, tmux, htop, fzf, etc.)
- ✅ Fonts
- ✅ Snapshot system (Snapper)

### Tier 3 - Specialized Tools (tier3-standalone.sh)
Choose what you need:
- CAD & 3D Modeling (FreeCAD, Blender, OpenSCAD)
- 3D Printing (Cura, PrusaSlicer, OrcaSlicer)
- Gaming (Steam, Lutris, Wine, Proton)
- Security Research (nmap, Wireshark, Metasploit, Burp Suite)
- Virtualization (QEMU, Docker, Podman, kubectl)
- Knowledge Preservation (Kiwix, Calibre, Zotero)
- Scientific Computing (Jupyter, R, Octave, MATLAB alternatives)
- Media Production (OBS, Kdenlive, Audacity, Ardour)
- Power Management (TLP, powertop)

## Boot Profiles (Ringed City)

At GRUB menu, choose your profile:

| Profile | Best For | Performance Impact |
|---------|----------|-------------------|
| **Midir (Balanced)** | Daily use, work | ~2-5% |
| **Gael (Max Security)** | Sensitive operations, hostile networks | ~15-30% |
| **Halflight (Performance)** | Gaming, media production | 0% |

## Common Commands

```bash
# Switch power profile
logos-power {gael|midir|halflight|status}

# System snapshots
sudo snapper list
sudo snapper -c root create --description "Before update"

# System update
sudo pacman -Syu
yay -Syu

# Boot into snapshot (via GRUB advanced options)
# Reboot → Advanced options → Select snapshot
```

## Troubleshooting

### "No network connectivity"
```bash
# For WiFi
iwctl
station wlan0 connect "NetworkName"
exit
ping archlinux.org
```

### "Wrong disk selected"
```bash
lsblk
# Verify your disk before confirming installation
```

### "Forgot LUKS passphrase"
⚠️ **No recovery possible** - LUKS encryption is designed to be unrecoverable without passphrase

### "Installation failed"
Check `/tmp/logos-install.log` for errors

## Installation Time

- **Core system**: ~10-15 minutes (depends on internet speed)
- **Tier 2 (Desktop)**: ~15-30 minutes
- **Tier 3 (Specialized)**: ~5-20 minutes per category

Total: **30-60 minutes** for complete installation

## System Requirements

- **Minimum**: 2-core CPU, 4GB RAM, 80GB storage
- **Recommended**: 4+ core CPU, 16GB RAM, 512GB NVMe SSD
- **UEFI**: Required (Legacy BIOS not supported)
- **Network**: Required during installation

## Next Steps After Installation

1. **Update system**: `sudo pacman -Syu`
2. **Configure desktop**: Settings → Personalize
3. **Add SSH keys**: `ssh-keygen -t ed25519`
4. **Configure UFW**: `sudo ufw allow 22/tcp` (if needed)
5. **Install additional software**: `yay -S <package>`
6. **Read full guide**: `LogOS_Build_Guide_2025_MASTER_v7.md`

## Getting Help

- **Full Documentation**: See `README.md` and `LogOS_Build_Guide_2025_MASTER_v7.md`
- **GitHub**: https://github.com/crussella0129/LogOS
- **Arch Wiki**: https://wiki.archlinux.org/

---

**Happy Installing! 🚀**

*LogOS - Ontology Substrate Operating System*
