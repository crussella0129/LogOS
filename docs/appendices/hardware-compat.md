# Hardware Compatibility

Extracted from the LogOS Master Specification. This appendix documents verified hardware, the GPU decision matrix, and known issues.

---

## Verified Hardware

| Hardware | Status | Secure Boot | Issues | Notes |
|----------|--------|-------------|--------|-------|
| **Laptops** |||||
| ThinkPad T480 | Verified | Works | None | Full compatibility, recommended |
| ThinkPad X1 Carbon Gen 9+ | Verified | Works | None | Excellent Linux support |
| Framework 13 (Intel) | Verified | Works | None | Ideal for repairs/upgrades |
| Framework 13 (AMD) | Verified | Works | WiFi needs `linux-firmware` | Add firmware package |
| Dell XPS 13/15 | Partial | Works | Fingerprint reader | Fingerprint may not work |
| HP EliteBook 800 series | Verified | Works | None | Good enterprise option |
| System76 (any) | Verified | Works | None | Designed for Linux |
| ASUS ROG laptops | Partial | Issues | NVIDIA + Secure Boot | Complex driver signing |
| MacBook (Intel) | Partial | Complex | T2 chip | Not recommended |
| **Desktops** |||||
| AMD Ryzen 5000/7000 series | Verified | Works | None | Excellent performance |
| AMD Ryzen 9000 series | Untested | Likely works | May need newer kernel | Use linux-zen |
| Intel 12th-14th Gen | Verified | Works | None | Full compatibility |
| **GPUs** |||||
| AMD RX 6000/7000 series | Verified | Works | None | Open-source drivers, recommended |
| AMD RX 9000 series | Untested | Likely works | May need mesa-git | Check kernel version |
| NVIDIA RTX 3000 series | Fragile | Complex | DKMS + Secure Boot | Complex driver signing |
| NVIDIA RTX 4000 series | Fragile | Complex | DKMS + Secure Boot | Complex driver signing |
| Intel Arc | Verified | Works | Needs recent kernel | linux-zen recommended |
| **Storage** |||||
| Samsung 980/990 Pro NVMe | Verified | N/A | None | Excellent performance |
| WD Black SN850X | Verified | N/A | None | Excellent performance |
| Any SATA SSD | Verified | N/A | None | Universal support |
| HDD (any) | Verified | N/A | Slower scrub | Consider SSD for boot |

---

## GPU Decision Matrix

```
                    ┌─────────────────────────────────────┐
                    │   Do you need CUDA for ML/LLM?      │
                    └─────────────────────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    ▼                               ▼
                   YES                              NO
                    │                               │
                    ▼                               ▼
        ┌───────────────────┐           ┌───────────────────┐
        │  NVIDIA Required  │           │  AMD Recommended  │
        │  Expect pain      │           │  Open-source FTW  │
        └───────────────────┘           └───────────────────┘
                    │                               │
                    ▼                               ▼
        ┌───────────────────┐           ┌───────────────────┐
        │  Secure Boot?     │           │  Any profile      │
        │  Option A: OFF    │           │  Full Secure Boot │
        │  Option B: sbctl  │           │  support          │
        └───────────────────┘           └───────────────────┘
```

---

## Minimum vs Recommended Specifications

| Component | Minimum | Recommended | Optimal (ML/Gaming) |
|-----------|---------|-------------|---------------------|
| CPU | x86_64, 2 cores | 4+ cores | 8+ cores with AVX2 |
| RAM | 4 GB | 16 GB | 32-64 GB |
| Storage | 120 GB | 512 GB NVMe | 1+ TB NVMe |
| GPU | Integrated | Discrete AMD | NVIDIA RTX 4070+ (CUDA) |
| Network | Ethernet | WiFi 6 + Ethernet | + SDR capability |
| TPM | None | TPM 2.0 | TPM 2.0 (for key sealing) |

---

## Known Problematic Hardware

| Hardware | Issue | Workaround |
|----------|-------|------------|
| Broadcom WiFi (older) | Poor Linux support | Replace with Intel |
| Realtek 8852BE WiFi | Unstable drivers | Use USB WiFi adapter |
| NVIDIA + Secure Boot | DKMS signing complexity | Disable Secure Boot or use sbctl |
| Apple T2 chip Macs | Locked bootloader | Not worth the effort |
| Some HP laptops | UEFI quirks | Check Arch Wiki for model |

---

## Pre-Purchase Checklist

Before buying hardware for LogOS:

1. Check Arch Wiki for hardware-specific issues
2. Verify WiFi chipset (Intel preferred)
3. Check if GPU is AMD (easier) or NVIDIA (harder)
4. Confirm UEFI boot support (not legacy BIOS only)
5. Check for coreboot/Libreboot availability (bonus)
6. Verify RAM is upgradeable if needed
7. Check storage interface (NVMe preferred)
