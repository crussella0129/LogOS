# LogOS Double Jump Installer (archinstall method)

This installer follows the archinstall-based method and splits the build into two jumps:
- Jump 1: Archinstall base system (manual menu-driven steps)
- Jump 2: LogOS transformation + optional desktop/apps/knowledge layers (scripts below)

## Phase 0 and Phase 1 (manual)

1) Boot the Arch ISO and connect to the network.
2) Update archinstall: `pacman -Sy archinstall`
3) Run: `archinstall`
4) Use these configuration choices:

- Language: English
- Keyboard layout: us (or your layout)
- Locale: en_US, UTF-8
- Mirrors: close to you or Worldwide
- Disk configuration: best-effort default layout
- Filesystem: btrfs
- LUKS2 encryption: enabled (strong passphrase)
- Bootloader: grub
- Swap: true (zram)
- Hostname: logos
- Root password: set
- User: create user, enable sudo
- Profile: minimal
- Audio: pipewire
- Kernels: linux only
- Additional packages: git vim nano base-devel networkmanager
- Network configuration: NetworkManager
- Timezone: your timezone
- NTP: true
- Optional repositories: multilib

When archinstall finishes, choose to chroot into the new installation.

## Phase 2 (LogOS transformation, in chroot)

Inside the chroot, run:

```
# Option A: clone the repo in the chroot
pacman -S --noconfirm git
git clone https://github.com/crussella0129/LogOS /root/LogOS
bash /root/LogOS/installer/phase2-transform.sh

# Option B: if the repo is already available under /root/LogOS
bash /root/LogOS/installer/phase2-transform.sh
```

Optional environment variables:
- `ENABLE_HARDENED=1` installs linux-hardened + headers
- `CRYPT_UUID_OVERRIDE` or `BTRFS_UUID_OVERRIDE` to force UUIDs

## Phase 3 (Desktop and apps, after reboot)

Run as root on the installed system:

```
bash /path/to/LogOS/installer/phase3-desktop.sh
```

Optional environment variables to enable categories:
- `INSTALL_OFFICE=1`
- `INSTALL_ENGINEERING=1`
- `INSTALL_DEV=1`
- `INSTALL_SECURITY=1`
- `INSTALL_RADIO=1`
- `INSTALL_GAMING=1`
- `INSTALL_MEDIA=1`
- `INSTALL_AUR=1` (requires `AUR_USER=<username>`)

## Phase 4 (Knowledge infrastructure)

```
INSTALL_OLLAMA=1 INSTALL_KIWIX=1 TARGET_USER=<username> bash /path/to/LogOS/installer/phase4-knowledge.sh
```

Notes:
- Phase 4 downloads large models and data; ensure stable internet.
- Scripts assume Arch Linux and `pacman`.
