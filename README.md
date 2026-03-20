# LogOS Gentoo

A Gentoo Linux-based operating system designed as an **Ontology Substrate OS** focused on knowledge preservation, security, sovereign compute, and survivability. **No systemd** — uses OpenRC for init.

> *"A civilization does not collapse when it loses data. It collapses when it loses procedural knowledge."*

## Overview

LogOS Gentoo (Version 2025.8 - Codename: "Ringed City") is a security-focused Linux distribution built on Gentoo Linux with OpenRC. It features:

- **OpenRC init** — no systemd dependency, full auditability, sovereign control over PID 1
- **Source-based package management** — Portage compiles everything from source, giving full control over USE flags, optimization, and dependency trees
- **Full-disk encryption** with LUKS2 and Argon2id
- **Btrfs filesystem** with snapshots and data integrity features
- **Ringed City boot profiles** with Dark Souls-themed security levels:
  - **Gael** — Maximum security for hostile environments
  - **Midir** — Balanced daily driver
  - **Halflight** — Performance mode for gaming/media
- **Knowledge infrastructure** with local LLM support (Ollama) and offline documentation (Kiwix)
- **Sovereign compute ready** — the system can bootstrap and rebuild itself entirely from source

## Why Gentoo + OpenRC

Gentoo was chosen as the substrate because:
- **Source compilation** gives absolute control — every binary on the system was built from auditable source
- **Portage USE flags** allow removing unwanted dependencies (including systemd) at compile time
- **OpenRC is Gentoo's default init** — this is not a hack or fork, it's the upstream default
- **Self-hosting** — with distfiles cached, the system can rebuild itself with no internet
- **Bleeding edge drivers** like Arch, but with more granular control

## Repository Structure

```
LogOS/
├── installer/
│   ├── build-vm.sh          # Single-script VM builder (losetup, LUKS2, Btrfs, OpenRC)
│   ├── clean.sh             # Build artifact teardown
│   └── configs/
│       ├── make.conf         # Portage configuration (USE="-systemd")
│       ├── package.use/logos  # Per-package USE flags
│       └── package.license/logos
├── GECK/                     # LLM agent session context
│   ├── GECK_Inst.md          # Agent instructions
│   ├── LLM_init.md           # Project goals
│   ├── tasks.md              # Current work items
│   ├── env.md                # Environment snapshot
│   └── log.md                # Session history
└── README.md
```

## Building the VM

```bash
# From a Gentoo or Linux host with losetup, cryptsetup, sgdisk, qemu:
sudo ./installer/build-vm.sh
```

The build script:
1. Creates a 30G raw disk image
2. Partitions (EFI + Boot + LUKS2 Root)
3. Creates Btrfs subvolumes (@, @home, @snapshots, @log)
4. Downloads and extracts the latest Gentoo **OpenRC** stage3
5. Deploys Portage configs (make.conf with `-systemd`, package.use, package.license)
6. Chroots: syncs Portage, sets OpenRC profile, installs kernel + dracut + GRUB
7. Configures networking via dhcpcd (OpenRC service)
8. Converts to qcow2 and boots in QEMU

Environment variables for non-interactive builds:
- `LOGOS_USER_NAME=logos`
- `LOGOS_LUKS_PASS=<passphrase>`
- `LOGOS_ROOT_PASS=<password>`
- `LOGOS_USER_PASS=<password>`

## Sovereign Compute Readiness

LogOS Gentoo is designed to be self-sufficient. Ensure you have:

- **Distfiles cached** — `DISTDIR` in make.conf points to a preserved directory; all source tarballs are kept
- **Portage tree snapshot** — `emerge --sync` downloads the full package tree; keep a local copy
- **Compiler toolchain** — GCC, binutils, make, autotools, cmake, meson are installed as build dependencies
- **Offline documentation** — Kiwix with Wikipedia, Gentoo Wiki, Stack Overflow ZIM files
- **Bootstrap capability** — Gentoo's stage1/stage2/stage3 process means you can rebuild the entire system from a minimal seed

## Phases (Planned)

| Phase | Status | Description |
|-------|--------|-------------|
| A | In Progress | Bootable VM (login prompt, no desktop, OpenRC) |
| B | Planned | Ringed City GRUB profiles, multi-kernel, watchdog |
| C | Planned | Security hardening (sysctl, audit, AppArmor, UFW) |
| D | Planned | Desktop (KDE Plasma, GPU detection) |
| E | Planned | Knowledge tools (Ollama, Kiwix, Cold Canon) |

## Requirements

- x86_64 architecture
- UEFI-capable system (or QEMU with OVMF)
- 30GB+ storage for VM image
- Linux host with: losetup, cryptsetup, sgdisk, qemu, btrfs-progs

## License

This project is licensed under the GNU General Public License v3.0 - see [LICENSE](LICENSE) for details.
