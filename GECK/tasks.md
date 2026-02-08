# Tasks — LogOS Gentoo

**Last Updated:** 2026-02-07

## Legend

- `[ ]` — Not started
- `[x]` — Complete
- `[BLOCKED: reason]` — Cannot proceed
- `[DECISION: topic]` — Awaiting human input

## Current Sprint — Installer Port

### Sprint 1: Foundation
- [x] Create `installer-gentoo/` directory structure
- [x] Write `lib/common.sh` — logging, error handling, root check
- [x] Write `lib/portage.sh` — emerge wrapper, overlay helpers
- [x] Write `lib/uuid.sh` — UUID detection
- [x] Write `configs/make.conf.base` + `package.use/` files
- [x] Write `configs/package.accept_keywords/`, `package.license/`
- [x] Write `phase0-partition.sh` — LUKS2 + Argon2id, Btrfs, 6 subvolumes
- [x] Write `phase1-stage3.sh` — stage3 bootstrap + chroot setup

### Sprint 2: Security Transform
- [x] Write `configs/dracut.conf`
- [x] Write `phase2-transform.sh` — kernels, security packages, services
- [x] Write `security/99-logos-hardening.conf` (sysctl)
- [x] Write `security/logos-audit.rules`
- [x] Write `security/10-logos-ssh.conf`
- [x] Write `grub/41_logos_profiles` — Ringed City with dynamic kernel resolution
- [x] Write `grub/grub-defaults`

### Sprint 3: Graceful Degradation
- [x] Write `kernel/kernel-watchdog.sh`
- [x] Write `services/logos-kernel-watchdog.service` + `.timer`
- [x] Write `tools/logos-validate-boot`

### Sprint 4: Desktop + Knowledge
- [x] Write `phase3-desktop.sh` — KDE, GPU, package categories, SDR, spectral
- [x] Write `phase4-knowledge.sh` — Ollama, Kiwix, Canon
- [x] Write `tools/logos-assist`
- [x] Write `tools/logos-canon-promote`

### Sprint 5: Overlay + Docs
- [x] Set up `overlays/logos-overlay/` structure (metadata, profiles)
- [x] Write `installer-gentoo/README.md`
- [x] Update GECK tasks.md and log.md

## Backlog — Verification & Iteration

- [x] Test Phase 0-1 in QEMU/KVM (36+41 PASS, 0 FAIL — via NBD against qcow2)
- [x] Test Phase 2 (110 PASS, 0 FAIL — GRUB profiles, security, watchdog, tools)
- [x] Test Phase 3+4 logic (203 PASS, 0 FAIL — script structure, packages, GPU, overlays, Canon, tools)
- [ ] Test Phase 3 desktop load (KDE Plasma boots — requires full VM boot with sudo)
- [x] Build VM infrastructure (build-bootable.sh — NBD+chroot approach)
- [x] Fix make.conf portage compatibility ($(nproc) → @NPROC@ placeholder)
- [x] Security audit all installer scripts (30 issues: 5 CRITICAL, 7 HIGH fixed)
- [x] Fix medium-severity audit findings (crypttab, mount verification, GPU detection)
- [x] Test kernel degradation (watchdog logic verified: whitelist, counter, Gael fallback)
- [x] Run `logos-validate-boot` — script validates all 10+ check categories
- [x] Create ebuilds in logos-overlay for: sdrangel, obsidian-bin, kiwix-tools, kiwix-desktop, shannon
- [x] Evaluate Shannon (KeygraphHQ/shannon — autonomous AI pentester, TypeScript/Docker, AGPL-3.0)
- [ ] Kernel boots successfully on target hardware
- [ ] System remains stable under load

## Completed (Recent)

- [x] Compile task list from log and LLM_init entries
- [x] Full installer-gentoo/ port from Arch → Gentoo (all 5 sprints)
