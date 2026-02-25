# Threat Model & Security Architecture

Extracted from the LogOS Master Specification. This appendix documents the formal threat model, security boundaries, and profile selection guide.

---

## Formal Threat Model

| Threat | Attack Vector | Mitigation | Residual Risk | Profile Response |
|--------|---------------|------------|---------------|------------------|
| **Physical disk theft** | Attacker obtains powered-off device | LUKS2 + Argon2id encryption | Evil maid attack (hardware keylogger, modified bootloader) | All profiles |
| **Evil maid** | Attacker modifies bootloader while unattended | Secure Boot + sbctl signing | Firmware-level compromise | Gael (lockdown) |
| **Remote exploitation** | Network-based attack on running services | UFW default-deny, fail2ban, AppArmor | Zero-day in allowed services | Gael, Midir |
| **Supply chain compromise** | Malicious packages in repos | GPG verification, official repos only | Compromised upstream | All profiles |
| **Silent data corruption** | Storage media degradation (bitrot) | Btrfs checksums + scrub + copies=2 | Controller firmware bugs | Cold Canon protected |
| **Operator error** | Accidental deletion, bad update | Snapper snapshots, grub-btrfs rollback | Judgment failures | Snapshot system |
| **Side-channel attacks** | Spectre, Meltdown, MDS, etc. | Kernel mitigations, SMT disable | Performance cost, incomplete coverage | Gael (full), Midir (auto) |
| **Network surveillance** | Traffic interception, metadata analysis | Tor, I2P, VPN, mesh networks | Endpoint compromise | Optional overlays |
| **LLM hallucination** | AI recommends destructive action | Constitutional constraints, sandboxing | Novel failure modes | LLM layer design |
| **Infrastructure collapse** | No internet, no power grid | Offline-first design, solar/battery | Total civilizational collapse | Core design tenet |

---

## Security Boundaries

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           TRUST BOUNDARY: HARDWARE                          │
│  TPM (optional) │ UEFI Firmware │ Storage Controller │ Network Interface   │
├─────────────────────────────────────────────────────────────────────────────┤
│                           TRUST BOUNDARY: BOOT                              │
│  Secure Boot Chain: shim → GRUB → kernel → initramfs → systemd             │
│  LUKS unlock occurs here — passphrase is the root of trust                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                           TRUST BOUNDARY: KERNEL                            │
│  Ringed City Profile Selection: Gael │ Midir │ Halflight                   │
│  AppArmor LSM │ Audit Subsystem │ Kernel Hardening (sysctl)                │
├─────────────────────────────────────────────────────────────────────────────┤
│                           TRUST BOUNDARY: USERSPACE                         │
│  Root (uid 0) │ Wheel Group │ Standard User │ Sandboxed Processes          │
├─────────────────────────────────────────────────────────────────────────────┤
│                           TRUST BOUNDARY: LLM LAYER                         │
│  Runs as unprivileged user │ No direct system modification │ Advisory only │
│  Constitutional constraints │ Command validation │ Logged actions          │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## What LogOS Does NOT Protect Against

- **Nation-state adversaries with physical access**: Encryption buys time, not immunity
- **Firmware/UEFI rootkits**: Below our trust boundary without specialized hardware
- **Compromised upstream Arch repositories**: We verify signatures, but trust Arch's infrastructure
- **User who ignores all warnings**: No system survives determined self-sabotage
- **Hardware failure**: Btrfs detects corruption but cannot resurrect dead drives — backups are required
- **Rubber-hose cryptanalysis**: No technical solution to physical coercion

---

## Security Profile Selection Guide

| Scenario | Recommended Profile | Rationale |
|----------|---------------------|-----------|
| Crossing international border | Gael | Assume device inspection, maximum hardening |
| Coffee shop / public WiFi | Midir | Network threats elevated, but need usability |
| Home network, trusted environment | Midir | Balanced default |
| Gaming session | Halflight | Performance priority, isolated activity |
| Processing sensitive documents | Gael | Data protection paramount |
| CAD/3D modeling | Midir or Halflight | Depends on data sensitivity |
| Penetration testing lab | Midir | Security tools need network access |
| Air-gapped secure workstation | Gael | Maximum isolation |
| Field deployment (solar/battery) | Midir | Balance security with power efficiency |
| Emergency/disaster response | Halflight | Speed over security when lives at stake |
