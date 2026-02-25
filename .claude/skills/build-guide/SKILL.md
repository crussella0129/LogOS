---
name: build-guide
description: Reference LogOS README (the single source of truth) when modifying installer scripts, security config, boot profiles, or architecture decisions. Invoke automatically when editing files in scripts/ or lib/.
user-invocable: false
---

# LogOS Build Guide Reference

When modifying any installer script in this repository, you MUST first read the relevant sections of `README.md` to ensure changes align with the build specification. The README is the single source of truth for the LogOS build.

## When to Consult the README

- Editing `scripts/01-disk-setup.sh` → Read sections 6 (Disk Setup): partition scheme, LUKS parameters, Btrfs subvolumes
- Editing `scripts/02-base-install.sh` → Read section 7 (Base Install): Tier 0/Tier 1 package strategy
- Editing `scripts/03-chroot-setup.sh` → Read section 9 (Chroot Configuration): mkinitcpio hook ordering
- Editing `scripts/04-bootloader.sh` → Read section 10 (Bootloader): Ringed City profiles, kernel parameters
- Editing `scripts/05-security.sh` → Read section 11 (Security Hardening): defense-in-depth, sysctl, SSH
- Editing `scripts/06-desktop.sh` → Read section 13 (Desktop): desktop stacks, GPU detection, themes
- Editing `scripts/07-packages.sh` → Read section 14 (Package Modules): AUR trust model
- Editing `scripts/08-knowledge.sh` → Read section 15 (Knowledge Infrastructure): Cold/Warm/Hot topology
- Editing `scripts/09-validate.sh` → Read section 16 (Validation)
- Adding/removing packages → Verify package names exist in Arch repos and match the README's package lists
- Modifying security settings → Read section 11 and the Appendix threat model
- Changing boot profiles → Read the Ringed City Profiles table (Gael/Midir/Halflight) in section 10

## Key Architecture Constraints

- **Triple-kernel**: linux, linux-lts, linux-zen (linux-hardened is optional)
- **Ringed City profiles**: Gael (max security), Midir (balanced), Halflight (performance)
- **Encryption**: LUKS2 with Argon2id — never weaken crypto defaults
- **Filesystem**: Btrfs with snapshots — preserve subvolume layout
- **Security-first**: AppArmor + audit enabled before first boot
- **Offline-capable**: Knowledge infrastructure must work without network
