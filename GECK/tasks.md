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

- [ ] Test Phase 0-1 in QEMU/KVM (LUKS+Btrfs boots to login)
- [ ] Test Phase 2 (all 3 Ringed City profiles appear in GRUB)
- [ ] Test Phase 3 (KDE Plasma desktop loads)
- [ ] Test kernel degradation (`echo c > /proc/sysrq-trigger` → Gael fallback)
- [ ] Run `logos-validate-boot` — all checks pass
- [ ] Create ebuilds in logos-overlay for: sdrangel, obsidian, kiwix, shannon
- [ ] Evaluate Shannon (agentic network tool from GitHub)
- [ ] Kernel boots successfully on target hardware
- [ ] System remains stable under load

## Completed (Recent)

- [x] Compile task list from log and LLM_init entries
- [x] Full installer-gentoo/ port from Arch → Gentoo (all 5 sprints)
