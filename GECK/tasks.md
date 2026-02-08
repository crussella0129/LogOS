# Tasks — LogOS Gentoo

**Last Updated:** 2026-02-08

## Legend

- `[ ]` — Not started
- `[x]` — Complete
- `[BLOCKED: reason]` — Cannot proceed
- `[DECISION: topic]` — Awaiting human input

## Phase A — Bootable VM

### Rebuild
- [x] Delete old installer-gentoo/, installer-proto/, test-vm/, LLM Log Bank/
- [x] Create new installer/ directory structure
- [x] Write installer/configs/make.conf (minimal, -O2 -pipe, no ccache)
- [x] Write installer/configs/package.use/logos (kernel + LUKS USE flags)
- [x] Write installer/configs/package.license/logos (linux-firmware)
- [x] Write installer/build-vm.sh (single self-contained script, losetup, ~350 lines)

### Build & Test
- [ ] Run `sudo ./installer/build-vm.sh` — full VM build
- [ ] GRUB menu appears in QEMU serial console
- [ ] LUKS passphrase prompt works (REDACTED_PASS)
- [ ] systemd boots to login prompt
- [ ] Login as logos/logos succeeds
- [ ] Network (DHCP) works inside VM

## Phase B — LogOS Features (after boot works)

- [ ] Ringed City GRUB profiles (41_logos_profiles)
- [ ] Multi-kernel (zen-sources + gentoo-kernel fallback)
- [ ] Kernel watchdog + systemd service/timer
- [ ] Security hardening (sysctl, audit, SSH)
- [ ] Desktop (KDE Plasma, GPU detection)
- [ ] Knowledge tools (Ollama, Kiwix, Cold Canon)
- [ ] logos-overlay ebuilds (sdrangel, obsidian, kiwix, shannon)

## Backlog

- [ ] Hardware boot test (target machine)
- [ ] Stability under load
