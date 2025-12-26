# LogOS

An Arch Linux-based operating system designed as an **Ontology Substrate OS** focused on knowledge preservation, security, and survivability.

> *"A civilization does not collapse when it loses data. It collapses when it loses procedural knowledge."*

## Overview

LogOS (Version 2025.8 - Codename: "Ringed City") is a security-focused Linux distribution built on Arch Linux. It features:

- **Triple-kernel architecture** (linux, linux-lts, linux-zen) for flexibility and resilience
- **Ringed City boot profiles** with Dark Souls-themed security levels:
  - **Gael** - Maximum security for hostile environments
  - **Midir** - Balanced daily driver
  - **Halflight** - Performance mode for gaming/media
- **Full-disk encryption** with LUKS2 and Argon2id
- **Btrfs filesystem** with snapshots and data integrity features
- **Knowledge infrastructure** with local LLM support (Ollama) and offline documentation (Kiwix)
- **Comprehensive security hardening** including AppArmor, audit, UFW, and kernel hardening

## Installation

LogOS uses a phase-based installation approach built on top of archinstall:

| Phase | Description | Method |
|-------|-------------|--------|
| 0-1 | Base system via archinstall | Manual (menu-driven) |
| 2 | Security hardening and GRUB profiles | `phase2-transform.sh` (in chroot) |
| 3 | Desktop environment and applications | `phase3-desktop.sh` (after reboot) |
| 4 | Knowledge infrastructure | `phase4-knowledge.sh` |

See [installer/README.md](installer/README.md) for detailed installation instructions.

## Repository Structure

```
LogOS/
├── installer/              # Primary installation scripts (recommended)
│   ├── phase2-transform.sh # Security/kernel hardening
│   ├── phase3-desktop.sh   # Desktop and optional packages
│   └── phase4-knowledge.sh # Ollama, Kiwix, logos-assist
├── installer-proto/        # Experimental archinstall plugin
│   ├── logos_bootloader.py # Bootloader plugin
│   └── logos_profile.py    # Installation profile
├── LLM Log Bank/           # Reference documentation for LLM agents
└── LogOS_Build_Guide_2025_MASTER_v7.md  # Master specification
```

## Optional Package Categories

Phase 3 supports modular installation of software categories via environment variables:

- `INSTALL_OFFICE=1` - LibreOffice, Thunderbird, Firefox, Obsidian, Zotero
- `INSTALL_ENGINEERING=1` - FreeCAD, OpenSCAD, KiCAD, Blender, PrusaSlicer
- `INSTALL_DEV=1` - VS Code, Git, Python, Node.js, Docker
- `INSTALL_SECURITY=1` - Wireshark, nmap, tcpdump, aircrack-ng, hashcat
- `INSTALL_RADIO=1` - GQRX, GNU Radio, Direwolf, FLDIGI
- `INSTALL_GAMING=1` - Steam, Lutris, Wine, GameMode, MangoHUD
- `INSTALL_MEDIA=1` - VLC, OBS, Kdenlive, GIMP, Inkscape, Audacity

## Requirements

- x86_64 architecture (ARM64 on roadmap)
- UEFI-capable system
- Minimum 40GB storage (recommended: 256GB+ for knowledge infrastructure)
- Stable internet connection for installation

## License

This project is licensed under the GNU General Public License v3.0 - see [LICENSE](LICENSE) for details.
