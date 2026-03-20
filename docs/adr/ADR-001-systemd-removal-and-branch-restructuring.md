# ADR-001: Remove systemd Dependency and Restructure Branches

**Status:** Accepted
**Date:** 2026-03-20
**Deciders:** Charles Russella

## Context

Systemd has merged a PR adding compliance with California age-verification laws, which function as a billionaire-funded data pipeline. For a project whose core mission is knowledge preservation and sovereign compute, depending on an init system that enforces external data-collection policy is a fundamental contradiction. LogOS must control its own boot chain.

Additionally, LogOS's long-term viability requires that every component can be rebuilt, replicated, and maintained without dependence on upstream decisions that compromise user sovereignty. The init system is the single most critical sovereignty boundary — it is PID 1, the root of all process control.

**Current state:**
- `LogOS-Arch` branch: Based on Arch Linux, uses systemd throughout (systemctl, systemd services, systemd-boot compatible GRUB chain). Recently refactored with 9-script installer, dotfiles, Hyprland desktop, logos.conf config system.
- `LogOS-Gentoo` branch: Based on Gentoo, uses systemd stage3 (`stage3-amd64-systemd`), systemd profile (`default/linux/amd64/23.0/systemd`), systemd-networkd, systemd-cryptsetup in dracut, `USE="systemd"` globally. Single build-vm.sh script.

**Forces at play:**
- Artix Linux is Arch without systemd — same repos, same packages, same rolling release, but with OpenRC/runit/dinit/s6 as init choices.
- Gentoo natively supports OpenRC as its default init system — systemd is the opt-in, not the default.
- OpenRC has the largest community and documentation base among non-systemd inits.
- Both branches must remain fully functional after the transition.
- Sovereign compute requirements demand that the system can rebuild itself entirely offline.

## Decision

1. **Rename `LogOS-Arch` to `LogOS-Artix`** — rebase the Arch installer on Artix Linux with OpenRC as init.
2. **Make `LogOS-Gentoo` systemd-free** — switch to OpenRC stage3, OpenRC profile, OpenRC services throughout.
3. **Add sovereign compute provisions** to both branches — source compilation toolchains, offline distfiles caching, bootstrap capability, offline documentation, and guidance for acquiring critical software while it remains freely available.

## Options Considered

### Option A: Artix + OpenRC (Both Branches)

| Dimension | Assessment |
|-----------|------------|
| Complexity | Medium — Artix is a direct Arch fork; Gentoo defaults to OpenRC |
| Compatibility | High — Artix uses Arch repos; Gentoo OpenRC is the upstream default |
| Community | Large — OpenRC is the most widely used non-systemd init |
| Sovereignty | Full — no telemetry, no external policy enforcement |
| Documentation | Excellent — Artix wiki + Arch wiki (translated); Gentoo Handbook defaults to OpenRC |

**Pros:**
- OpenRC is simple, dependency-based, shell-scriptable, auditable
- Artix maintains OpenRC service scripts for all major Arch packages
- Gentoo's native init is OpenRC — removing systemd simplifies the Gentoo build
- elogind provides logind API without systemd (needed for Wayland/KDE/Hyprland)
- dracut works without systemd modules (uses `crypt` instead of `systemd-cryptsetup`)

**Cons:**
- Some packages assume systemd (e.g., GNOME hard-depends on it) — not relevant since LogOS uses Hyprland/KDE
- Service management syntax changes across all scripts
- Need to verify every `systemctl enable` has an OpenRC equivalent

### Option B: Runit (Artix Branch Only)

| Dimension | Assessment |
|-----------|------------|
| Complexity | Medium |
| Compatibility | Medium — smaller service script ecosystem than OpenRC |
| Community | Small-Medium |
| Sovereignty | Full |
| Documentation | Limited compared to OpenRC |

**Pros:** Extremely simple (each service is a directory with a `run` script), fast boot
**Cons:** Smaller ecosystem, fewer pre-packaged service scripts, Gentoo doesn't natively support runit well

### Option C: Stay on Systemd, Patch Out Telemetry

| Dimension | Assessment |
|-----------|------------|
| Complexity | Low initially, high ongoing |
| Compatibility | High |
| Community | Largest |
| Sovereignty | Partial — requires ongoing audit of upstream changes |

**Pros:** No migration work, largest package ecosystem
**Cons:** Perpetual cat-and-mouse with upstream policy changes, contradicts project philosophy, cannot guarantee sovereignty

## Trade-off Analysis

**Option A wins decisively.** OpenRC is the only init that is both mature enough for production use AND natively supported by both Artix and Gentoo. Runit (Option B) would create a split where the Artix branch uses one init and Gentoo uses another. Option C is philosophically untenable.

The migration cost is bounded: every `systemctl enable X` maps to `rc-update add X default`, every `systemctl start X` maps to `rc-service X start`. The deeper changes are in dracut configuration (remove `systemd-initrd` and `systemd-cryptsetup` modules, use `crypt` module instead) and network configuration (replace `systemd-networkd` with NetworkManager+OpenRC or dhcpcd+OpenRC).

## Consequences

**What becomes easier:**
- Full auditability of the init chain — OpenRC scripts are plain shell
- No upstream policy surprises — OpenRC has no telemetry capability
- Gentoo builds are simpler — OpenRC is Gentoo's default, so we remove complexity
- System is fully self-hosting — no binary-only init components

**What becomes harder:**
- Some Arch wiki pages assume systemd — mental translation required
- Container integration (Docker uses systemd cgroups by default) — solvable with cgroupsv2 + elogind
- Future package adoption requires checking for systemd hard-dependencies

**What we'll need to revisit:**
- Docker/Podman cgroup configuration under OpenRC
- Wayland session management with elogind vs systemd-logind
- Any new upstream packages that hard-depend on systemd

## Sovereign Compute Provisions

Both branches must include:
1. **Compiler toolchain** — GCC, binutils, make, autotools, cmake, meson, cargo/rustup
2. **Source preservation** — Gentoo distfiles cache, Artix package cache, local mirrors
3. **Bootstrap capability** — ability to rebuild the entire system from source with no network
4. **Offline documentation** — Kiwix (Wikipedia, Arch Wiki), man pages, info pages
5. **Replication instructions** — clear guide for cloning the entire build environment to another machine
6. **Time-sensitive acquisition list** — software and datasets to download while freely available

## Action Items

1. [x] Write this ADR
2. [ ] Create `LogOS-Artix` branch from `LogOS-Arch`, convert all scripts to OpenRC
3. [ ] Convert `LogOS-Gentoo` to OpenRC stage3 and profile
4. [ ] Add sovereign compute provisions to both branches
5. [ ] Run `/engineering:review` on both branches
6. [ ] Update GitHub: rename remote branch, update default branch references
