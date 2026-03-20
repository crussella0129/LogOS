# Tasks — LogOS Gentoo

**Last Updated:** 2026-03-20

## Legend

- `[ ]` — Not started
- `[x]` — Complete
- `[BLOCKED: reason]` — Cannot proceed
- `[DECISION: topic]` — Awaiting human input

## Phase A — Bootable VM (OpenRC)

### Rebuild
- [x] Delete old installer-gentoo/, installer-proto/, test-vm/, LLM Log Bank/
- [x] Create new installer/ directory structure
- [x] Write installer/configs/make.conf (minimal, -O2 -pipe, no ccache)
- [x] Write installer/configs/package.use/logos (kernel + LUKS USE flags)
- [x] Write installer/configs/package.license/logos (linux-firmware)
- [x] Write installer/build-vm.sh (single self-contained script, losetup, ~350 lines)
- [x] Convert from systemd to OpenRC (stage3, profile, dracut, networking, services)

### Build & Test
- [ ] Run `sudo ./installer/build-vm.sh` — full VM build
- [ ] GRUB menu appears in QEMU serial console
- [ ] LUKS passphrase prompt works
- [ ] OpenRC boots to login prompt
- [ ] Login as logos/logos succeeds
- [ ] Network (DHCP via dhcpcd) works inside VM

## Phase B — LogOS Features (after boot works)

- [ ] Ringed City GRUB profiles (41_logos_profiles)
- [ ] Multi-kernel (zen-sources + gentoo-kernel fallback)
- [ ] Kernel watchdog + OpenRC cron-based health check
- [ ] Security hardening (sysctl, audit, SSH)
- [ ] Desktop (KDE Plasma, GPU detection)
- [ ] Knowledge tools (Ollama, Kiwix, Cold Canon)
- [ ] logos-overlay ebuilds (sdrangel, obsidian, kiwix, shannon)

## Phase C — Sovereign Compute

- [ ] Cache distfiles for offline rebuilds
- [ ] Local portage tree snapshot
- [ ] Compiler toolchain self-hosting verification
- [ ] Offline documentation (Kiwix ZIM files)
- [ ] Bootstrap guide: rebuild from stage3 with no internet

## Backlog

- [ ] Hardware boot test (target machine)
- [ ] Stability under load
