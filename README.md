# LogOS — Ontology Substrate Operating System

**Version:** 2025.8 (Ringed City)
**Base:** Arch Linux | **Architecture:** x86_64

> *"A civilization does not collapse when it loses data. It collapses when it loses procedural knowledge."*

LogOS is an Arch Linux-based operating system designed for knowledge preservation and survivability. It provides a hardened, encrypted, offline-capable system with on-the-metal LLM inference and a three-tier knowledge preservation topology.

---

## How to Use This Repo

This repository is a **literate build guide** — the documentation IS the source of truth, and companion scripts automate what the guide explains.

1. [`docs/build-guide.md`](docs/build-guide.md) — **Start here.** The complete build guide explains *what* and *why* for every step.
2. `scripts/` — Numbered companion scripts referenced by the guide. Each is independently runnable.
3. `lib/` — Shared functions sourced by all scripts.
4. `logos.conf.example` — All user choices in one file. Copy to `logos.conf` and edit.

You can follow the guide and run scripts, or read the guide and type every command manually. Either way, you understand what you're building.

---

## Quick Start

```bash
# 1. Download and verify the Arch Linux ISO
#    (see docs/build-guide.md Section 1)

# 2. Clone this repo (on any machine with git)
git clone https://github.com/crussella0129/LogOS-Arch.git
cd LogOS-Arch

# 3. Configure
cp logos.conf.example logos.conf
# Edit logos.conf — at minimum set LOGOS_DISK, LOGOS_HOSTNAME, LOGOS_USERNAME, LOGOS_TIMEZONE

# 4. Follow the guide
#    Boot the Arch ISO, then follow docs/build-guide.md section by section
```

---

## Ringed City Boot Profiles

Named after bosses from Dark Souls 3's "The Ringed City" DLC:

| Profile | Kernel | Security | Use Case | Perf. Impact |
|---------|--------|----------|----------|-------------|
| **Gael** | linux-lts | Maximum — lockdown, no SMT, full LSM | Hostile environments | ~15-30% |
| **Midir** | linux-zen | Balanced — auto mitigations, AppArmor | Daily driver | ~2-5% |
| **Halflight** | linux-zen | Minimal — mitigations off | Gaming, media, HPC | None |

---

## Repository Structure

```
LogOS-Arch/
├── docs/
│   ├── build-guide.md              # The literate build guide (start here)
│   └── appendices/
│       ├── threat-model.md         # Formal threat model + security boundaries
│       ├── hardware-compat.md      # Verified hardware + GPU decision matrix
│       └── troubleshooting.md      # Failure modes + recovery procedures
├── scripts/
│   ├── 00-verify-env.sh            # Live environment checks
│   ├── 01-disk-setup.sh            # Partitioning + LUKS + Btrfs
│   ├── 02-base-install.sh          # pacstrap + fstab
│   ├── 03-chroot-setup.sh          # System identity + initramfs
│   ├── 04-bootloader.sh            # GRUB + Ringed City profiles
│   ├── 05-security.sh              # Sysctl, AppArmor, UFW, fail2ban, SSH
│   ├── 06-desktop.sh               # Desktop dispatcher (multi-DE)
│   ├── 07-packages.sh              # Modular package categories
│   ├── 08-knowledge.sh             # Cold Canon + Ollama + Kiwix
│   └── 09-validate.sh              # Post-build validation suite
├── lib/
│   ├── common.sh                   # Shared logging, config, helpers
│   ├── detect.sh                   # Hardware detection functions
│   ├── desktop.sh                  # Shared desktop library (themes, templates)
│   ├── desktop-hyprland.sh         # Hyprland packages + config
│   ├── desktop-kde.sh              # KDE Plasma packages + config
│   ├── desktop-sway.sh             # Sway packages + config
│   └── desktop-i3.sh               # i3 packages + config
├── dotfiles/
│   ├── themes/                     # Color palettes (ringed-city, catppuccin, dracula)
│   ├── hyprland/                   # Hyprland configs (hypr, waybar, rofi, dunst)
│   ├── sway/                       # Sway configs (sway, waybar, mako)
│   └── shared/                     # Cross-desktop (kitty, alacritty, starship, GTK)
├── archive/
│   └── LogOS_Build_Guide_2025_MASTER_v7.md  # Original master spec (reference)
├── LLM Log Bank/                   # Historical session logs
├── logos.conf.example              # Configuration template
├── LICENSE                         # GPLv3
└── .gitignore
```

---

## Script Reference

| Script | Description | Context |
|--------|-------------|---------|
| `00-verify-env.sh` | UEFI, network, clock, keyring, mirrors | Live USB |
| `01-disk-setup.sh` | Partition, encrypt, create Btrfs subvolumes | Live USB |
| `02-base-install.sh` | pacstrap Tier 0+1, generate fstab | Live USB |
| `03-chroot-setup.sh` | Timezone, locale, user, mkinitcpio | arch-chroot |
| `04-bootloader.sh` | GRUB install, Ringed City profiles | arch-chroot |
| `05-security.sh` | Kernel hardening, firewall, fail2ban, SSH | chroot or booted |
| `06-desktop.sh` | Desktop (Hyprland/KDE/Sway/i3), Pipewire, GPU, themes | Booted system |
| `07-packages.sh` | Office, dev, security, radio, gaming, media, engineering | Booted system |
| `08-knowledge.sh` | Cold Canon dirs, Ollama, Kiwix, branding | Booted system |
| `09-validate.sh` | Read-only validation of all subsystems | Booted system |

---

## Key Features

- **Multi-desktop architecture** — Hyprland (default), KDE Plasma, Sway, i3
- **Ringed City theme** — Dark Souls aesthetic with ember/gold accents; also ships Catppuccin Mocha and Dracula
- **Template-based theming** — all dotfiles themed at install time via `@@THEME_*@@` substitution
- **Triple-kernel architecture** — linux, linux-lts, linux-zen (optional linux-hardened)
- **LUKS2 + Argon2id** full-disk encryption
- **Btrfs** with 7 subvolumes, snapshots, compression, and copies=2 for archival data
- **Pre-boot security** — AppArmor, audit, kernel hardening configured before first boot
- **Defense in depth** — sysctl hardening, UFW firewall, fail2ban, SSH hardening
- **Offline knowledge** — Ollama (local LLM), Kiwix (offline Wikipedia/docs)
- **Cold Canon** — bitrot-protected archival storage with promotion pipeline
- **Modular packages** — 7 optional categories, toggled via config file

---

## Requirements

- x86_64 architecture with UEFI support
- 120 GB minimum storage (512 GB+ recommended)
- 4 GB RAM minimum (16 GB+ recommended)
- Internet connection for initial installation

---

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE).
