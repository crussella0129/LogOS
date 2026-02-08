# LogOS Gentoo Installer

Phase-based installation scripts for LogOS on Gentoo Linux.

## Overview

LogOS Gentoo is the second generation of LogOS, ported from Arch Linux to Gentoo for deeper customizability and source-based optimization. It preserves the Ringed City architecture: multi-kernel boot profiles, LUKS2 full-disk encryption, Btrfs subvolumes, and the Cold Canon knowledge topology.

## Installation Phases

| Phase | Script | Description | Environment |
|-------|--------|-------------|-------------|
| 0 | `phase0-partition.sh` | Disk partitioning, LUKS2 encryption, Btrfs subvolumes | Live USB |
| 1 | `phase1-stage3.sh` | Stage3 download/extract, portage setup, chroot config | Live USB |
| 2 | `phase2-transform.sh` | Kernels, GRUB Ringed City profiles, security hardening | Chroot |
| 3 | `phase3-desktop.sh` | KDE Plasma, GPU drivers, optional package categories | Booted system |
| 4 | `phase4-knowledge.sh` | Ollama LLM, Kiwix, Cold Canon, logos-assist CLI | Booted system |

## Quick Start

```bash
# Boot from Gentoo minimal install CD

# Phase 0: Partition and encrypt disk
DISK=/dev/sda ./phase0-partition.sh

# Phase 1: Bootstrap Gentoo
TARGET_USER=charles TARGET_HOSTNAME=logos ./phase1-stage3.sh

# Phase 2: Security transform (inside chroot)
chroot /mnt /bin/bash
cd /path/to/installer-gentoo
./phase2-transform.sh

# Reboot into new system, then:

# Phase 3: Desktop (enable categories as needed)
INSTALL_DEV=1 INSTALL_SECURITY=1 ./phase3-desktop.sh

# Phase 4: Knowledge infrastructure
INSTALL_OLLAMA=1 TARGET_USER=charles ./phase4-knowledge.sh
```

## Ringed City Boot Profiles

| Profile | Kernel | Security Level | Use Case |
|---------|--------|---------------|----------|
| **Gael** | gentoo-kernel (or hardened) | Maximum — nosmt, lockdown, full mitigations | Hostile networks, sensitive work |
| **Midir** | zen-sources | Balanced — standard mitigations, AppArmor | Daily driver |
| **Halflight** | zen-sources | Minimal — mitigations off, no audit | Gaming, media production |

## Graceful Kernel Degradation

If a kernel panic occurs, GRUB automatically falls back to the next entry. The `logos-kernel-watchdog` service runs 90 seconds after boot to verify system health:

- Checks: AppArmor, auditd, UFW, NetworkManager active; kernel not tainted
- Healthy: confirms current kernel as GRUB default
- Unhealthy: increments failure counter; after 2 failures, locks to Gael

Degradation always moves toward **more secure** (Gael), never toward Halflight. The boot counter is stored on the LUKS-encrypted filesystem and the watchdog only writes whitelisted GRUB entry names.

## Optional Package Categories

Set environment variables to `1` before running `phase3-desktop.sh`:

| Variable | Packages |
|----------|----------|
| `INSTALL_OFFICE` | LibreOffice, Thunderbird, Firefox, Chromium |
| `INSTALL_ENGINEERING` | FreeCAD, OpenSCAD, KiCAD, Blender |
| `INSTALL_DEV` | VS Code, Git, Python, Node.js, Docker |
| `INSTALL_SECURITY` | Wireshark, nmap, hashcat, metasploit (pentoo overlay) |
| `INSTALL_RADIO` | GNURadio, GQRX, Direwolf, FLDIGI, Xastir |
| `INSTALL_GAMING` | Steam, Lutris, Wine, GameMode, MangoHUD |
| `INSTALL_MEDIA` | VLC, OBS, Kdenlive, GIMP, Inkscape, Audacity |
| `INSTALL_SDR` | Extended SDR: rtl-sdr, hackrf-tools, SoapySDR |
| `INSTALL_SPECTRAL` | FFTW, SciPy, NumPy, Sonic Visualiser |
| `INSTALL_RUST_TOOLS` | ripgrep, fd, bat, eza, bottom, starship, tokei, dust, zoxide |

## Directory Structure

```
installer-gentoo/
  lib/
    common.sh              # Logging, error handling, root check
    portage.sh             # emerge wrapper, overlay helpers
    uuid.sh                # UUID detection
  phase0-partition.sh      # LUKS2 + Btrfs partitioning
  phase1-stage3.sh         # Stage3 bootstrap + chroot
  phase2-transform.sh      # Kernels + security hardening
  phase3-desktop.sh        # Desktop + optional packages
  phase4-knowledge.sh      # LLM + knowledge infrastructure
  configs/
    make.conf.base         # Portage global config
    package.use/           # Per-package USE flags
    package.accept_keywords/ # ~amd64 keywords
    package.license/       # License acceptance
    dracut.conf            # Initramfs config
  kernel/
    kernel-watchdog.sh     # Boot health watchdog
  grub/
    41_logos_profiles      # Ringed City GRUB generator
    grub-defaults          # /etc/default/grub template
  security/
    99-logos-hardening.conf # sysctl hardening
    logos-audit.rules      # Audit rules
    10-logos-ssh.conf      # SSH hardening
  services/
    logos-kernel-watchdog.service
    logos-kernel-watchdog.timer
  tools/
    logos-assist           # LLM CLI
    logos-canon-promote    # Canon governance tool
    logos-validate-boot    # Post-boot validation
  overlays/
    logos-overlay/         # Custom ebuilds
```

## Key Differences from Arch

| Aspect | Arch | Gentoo |
|--------|------|--------|
| Package manager | pacman | emerge (Portage) |
| Initramfs | mkinitcpio | dracut |
| Kernel (stable) | linux-lts | gentoo-kernel (prebuilt) |
| Kernel (performance) | linux-zen | zen-sources (compiled) |
| AUR replacement | yay (AUR) | Custom overlay + pentoo |
| Init system | systemd | systemd (same) |
| Profile system | N/A | eselect profile |
| Base install | archinstall / pacstrap | stage3 tarball |

## Verification

```bash
# Validate full system configuration
logos-validate-boot --verbose

# Test in QEMU/KVM
qemu-system-x86_64 -enable-kvm -m 8G -cpu host \
  -drive file=logos.qcow2,format=qcow2 \
  -bios /usr/share/ovmf/OVMF.fd

# Test kernel degradation (in VM only!)
echo c > /proc/sysrq-trigger  # trigger panic → verify Gael fallback
```
