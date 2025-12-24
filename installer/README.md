# LogOS Automated Installer

Complete automated installation system for LogOS (Ontology Substrate Operating System).

## Overview

This installer automates the complete LogOS installation process from bare metal to a fully configured, secure, encrypted Arch Linux-based system with the Ringed City triple-kernel architecture.

## Features

- Fully automated guided installation with minimal user input
- LUKS2 encryption, AppArmor, audit, UFW, fail2ban pre-configured
- Tiered installation: Tier 0 (Boot), Tier 1 (Security), Tier 2 (Desktop), Tier 3 (Specialized)
- Ringed City profiles: Gael, Midir, Halflight
- Btrfs subvolumes with snapshots and rollback
- Multiple desktop environments: GNOME, KDE, XFCE, i3-wm, or headless
- GPU support: AMD, NVIDIA, Intel auto-detection
- Branding: custom GRUB splash and desktop wallpaper
- Specialized tools: CAD, 3D printing, gaming, security research, scientific computing

## Quick Start

### Prerequisites

1. **Arch Linux ISO**: Download from https://archlinux.org/download/
2. **Target Hardware**:
   - x86_64 CPU (2+ cores recommended)
   - 4GB+ RAM (16GB recommended)
   - 80GB+ storage (512GB recommended)
   - UEFI firmware (Legacy BIOS not supported)
3. **Network Connection**: Required for package downloads

### Installation Steps

#### 1. Boot into Arch Linux Live Environment

- Create bootable USB with Arch Linux ISO
- Boot from USB in UEFI mode
- Disable Secure Boot (temporarily - can be re-enabled after installation)

#### 2. Download the Installer

```bash
# BARE METAL - ETHERNET OR VM:
ping archlinux.org # to ensure you have a connection (do not copy this comment).
# then ctrl+c (to stop pinging if successfully receiving a response)

# BARE METAL - WIFI
# Connect to network (if using WiFi)
iwctl
# In iwctl prompt:
# station wlan0 connect "YourNetworkName"
# exit
# Test connection with the instructions for "BARE METAL - ETHERNET OR VM" (Above)

# Download installer from GitHub
pacman -Sy git
git clone https://github.com/crussella0129/LogOS.git
cd LogOS/installer
chmod +x logos-install.sh
```

#### 3. Run the Installer

```bash
# Start installation
./logos-install.sh
```

The installer will:
1. Verify UEFI mode and network connectivity
2. Prompt for configuration (disk, hostname, passwords, etc.)
3. Partition and encrypt the disk
4. Install Tier 0 (boot-critical) and Tier 1 (security) packages
5. Configure the system in chroot
6. Install GRUB with Ringed City boot profiles
7. Finalize and prepare for first boot

#### 4. First Boot

After installation completes:

```bash
# Remove USB installation media
# Reboot
systemctl reboot
```

At the GRUB menu, select your preferred boot profile:
- **Midir (Balanced)** - Recommended for daily use
- **Gael (Maximum Security)** - For high-risk operations
- **Halflight (Performance)** - For gaming/media production

Login with your username and password.

#### 5. Post-Installation (Optional)

After first boot, install additional components:

**Tier 2 (Desktop & Workstation)**:
```bash
cd /path/to/LogOS/installer/modules
chmod +x tier2-standalone.sh
./tier2-standalone.sh
```

This installs:
- Graphics drivers
- Desktop environment
- Essential applications
- Development tools
- Terminal enhancements
- Fonts
- Snapshot system

**Tier 3 (Specialized Capabilities)**:
```bash
chmod +x tier3-standalone.sh
./tier3-standalone.sh
```

Choose from:
- CAD & 3D Modeling
- 3D Printing tools
- Gaming (Steam, Lutris, etc.)
- Security Research tools
- Virtualization & Containers
- Knowledge Preservation (Kiwix, Calibre)
- Scientific Computing
- Media Production
- Power Management

## Configuration Options

### Supported Desktop Environments

- **GNOME** (Recommended for workstations)
- **KDE Plasma** (Power users, gaming)
- **XFCE** (Lightweight)
- **i3-wm** (Tiling window manager)
- **None** (Server/minimal installation)

### GPU Support

- **AMD**: Fully supported, open-source drivers (recommended)
- **NVIDIA**: Proprietary drivers with CUDA support (requires additional configuration for Secure Boot)
- **Intel**: Fully supported, open-source drivers
- **Integrated**: Basic support

### Ringed City Boot Profiles

| Profile | Kernel | Security | Use Case | Performance |
|---------|--------|----------|----------|-------------|
| **Gael** | linux-lts | Maximum (SMT disabled, lockdown) | Border crossing, hostile networks | -15-30% |
| **Midir** | linux-zen | Balanced (auto mitigations) | Daily secure operations | -2-5% |
| **Halflight** | linux-zen | Performance (mitigations off) | Gaming, media, HPC | 0% |

Switch profiles at boot via GRUB menu.

## Architecture

### Partition Scheme

```
/dev/sdX1   1GB   FAT32   /boot/efi   (EFI System Partition)
/dev/sdX2   4GB   ext4    /boot       (Unencrypted boot)
/dev/sdX3   Rest  LUKS2   (Encrypted container)
  - Btrfs subvolumes:
    - @          -> /
    - @home      -> /home
    - @snapshots -> /.snapshots
    - @canon     -> /home/<user>/Documents (Cold Canon, copies=2)
    - @mesh      -> /home/<user>/Sync (Warm Mesh)
    - @log       -> /var/log
    - @cache     -> /var/cache
```

### Security Features

- **LUKS2 Encryption**: Argon2id key derivation, AES-XTS-PLAIN64
- **AppArmor**: Mandatory Access Control
- **Audit**: System call auditing
- **UFW**: Firewall (default deny)
- **fail2ban**: Intrusion prevention
- **Hardened SSH**: No root login, key-based auth recommended
- **Kernel Hardening**: sysctl security parameters
- **Optional Secure Boot**: sbctl key management

### Btrfs Features

- **Transparent Compression**: zstd (space-efficient, fast)
- **Checksumming**: Detects silent data corruption
- **Snapshots**: Via Snapper, automatic timeline
- **Rollback**: Via grub-btrfs (boot into snapshots)
- **Bitrot Protection**: copies=2 on Cold Canon subvolume

## File Structure

```
installer/
- install-logos.sh              # Main installer script
- logos-install.sh              # Orchestrated installer (recommended)
- lib/
  - common.sh                   # Common functions (logging, colors, etc.)
  - validation.sh               # Input validation functions
  - logging.sh                  # Logging subsystem
  - error-handling.sh           # Error handling and cleanup
- modules/
  - 00-preflight.sh             # System validation
  - partitioning.sh             # Disk partitioning and encryption
  - tier0.sh                    # Tier 0: Boot-critical packages
  - tier1.sh                    # Tier 1: Security infrastructure
  - chroot.sh                   # System configuration in chroot
  - bootloader.sh               # GRUB and Ringed City profiles
  - 60-desktop.sh               # Desktop environment installation
  - tier2-standalone.sh         # Post-install: Desktop & workstation
  - tier3-standalone.sh         # Post-install: Specialized tools
- README.md                     # This file
```

## Troubleshooting

### Installation Fails at Tier 0

**Symptom**: Package installation errors

**Solutions**:
- Check network connectivity: `ping archlinux.org`
- Update archlinux-keyring: `pacman -S archlinux-keyring`
- Check mirror list: `/etc/pacman.d/mirrorlist`

### Cannot Boot After Installation

**Symptom**: GRUB menu doesn't appear or kernel panic

**Solutions**:
1. Boot from USB again
2. Open encrypted partition: `cryptsetup open /dev/sdX3 cryptroot`
3. Mount filesystems: `mount -o subvol=@ /dev/mapper/cryptroot /mnt`
4. Chroot: `arch-chroot /mnt`
5. Reinstall GRUB: `grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=LogOS`
6. Regenerate config: `grub-mkconfig -o /boot/grub/grub.cfg`

### NVIDIA + Secure Boot Issues

**Symptom**: Black screen after enabling Secure Boot with NVIDIA

**Solutions**:
- Disable Secure Boot in BIOS, OR
- Use sbctl to sign NVIDIA modules:
  ```bash
  sudo sbctl sign -s /boot/vmlinuz-linux*
  sudo sbctl sign -s /usr/lib/modules/*/misc/nvidia*.ko*
  ```

### Forgot LUKS Passphrase

**Symptom**: Cannot decrypt disk

**Solution**: There is no recovery if you lose the LUKS passphrase. This is by design for security. Always keep a secure backup of your passphrase.

## Advanced Usage

### Manual Installation

If you prefer manual installation, follow the complete build guide in `LogOS_Build_Guide_2025_MASTER_v7.md`.

### Customization

Edit the installer scripts to customize:
- Package lists (in `tier0.sh`, `tier1.sh`, `tier2-standalone.sh`)
- Partition sizes (in `partitioning.sh`)
- Security policies (in `chroot.sh`)
- Boot profiles (in `bootloader.sh`)

### Offline Installation

For fully offline installation:
1. Download all packages on a connected system
2. Copy to USB drive
3. Configure pacman to use local repository
4. Run installer

See `LogOS_Build_Guide_2025_MASTER_v7.md` Section 28 for details.

## System Management

### Snapshot Management

```bash
# List snapshots
sudo snapper list

# Create manual snapshot
sudo snapper -c root create --description "Before update"

# Rollback to snapshot (via GRUB)
# Reboot -> Advanced options -> Select snapshot
```

### Power Management

```bash
# Switch power profiles
logos-power gael      # Conservative
logos-power midir     # Balanced
logos-power halflight # Performance
logos-power status    # Show current status
```

### System Updates

```bash
# Update system
sudo pacman -Syu

# Update AUR packages
yay -Syu

# Clean package cache
sudo pacman -Sc
yay -Sc
```

## Contributing

This installer is part of the LogOS project. Contributions welcome:
- Bug reports: Open an issue
- Improvements: Submit a pull request
- Documentation: Help expand the guide

## License

See main repository LICENSE file.

## Support

- **Documentation**: `LogOS_Build_Guide_2025_MASTER_v7.md`
- **Repository**: https://github.com/crussella0129/LogOS
- **Arch Wiki**: https://wiki.archlinux.org/

## Version

- **Installer Version**: 2025.7
- **LogOS Version**: 2025.7
- **Codename**: Ringed City
- **Base**: Arch Linux

---

*"In the beginning was the Logos..."*

**LogOS**: An Ontology Substrate for human knowledge, creation, and survival.


