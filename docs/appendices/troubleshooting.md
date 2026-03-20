# Troubleshooting

Extracted from the LogOS Master Specification. This appendix covers failure modes, recovery procedures, and the emergency quick reference card.

---

## Common Failure Scenarios

| Symptom | Likely Cause | Recovery Section |
|---------|--------------|-----------------|
| Won't boot | GRUB/initramfs issue | GRUB Recovery |
| "cryptroot not found" | Missing encrypt hook | Encrypt Hook |
| Black screen after LUKS | Kernel panic or GPU issue | Black Screen |
| No network | NetworkManager issue | Network Issues |
| Kernel panic | Initramfs issue | Kernel Panic |
| Secure Boot failure | Unsigned kernel | Secure Boot |
| Emergency shell | Failed service | Emergency Shell |
| Btrfs corruption | Drive errors | Btrfs Corruption |

---

## Recovery Procedures

### Entering Recovery

All recovery starts the same way:

```bash
# 1. Boot from Arch Linux ISO
# 2. Open encrypted volume
cryptsetup open /dev/sdX3 cryptroot

# 3. Mount filesystems
mount -o subvol=@ /dev/mapper/cryptroot /mnt
mount /dev/sdX2 /mnt/boot
mount /dev/sdX1 /mnt/boot/efi

# 4. Chroot
artix-chroot /mnt

# 5. [Fix the problem - see below]

# 6. Exit and reboot
exit
umount -R /mnt
reboot
```

### GRUB Recovery

```bash
# Inside chroot:
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=LogOS
grub-mkconfig -o /boot/grub/grub.cfg
```

### Missing Encrypt Hook

```bash
# Verify mkinitcpio.conf contains encrypt hook
grep HOOKS /etc/mkinitcpio.conf
# Should include: encrypt

# If missing, fix it:
# Edit /etc/mkinitcpio.conf and ensure HOOKS contains:
# (base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt btrfs filesystems fsck)

# Regenerate
mkinitcpio -P
```

### Black Screen After LUKS

```bash
# Usually GPU driver issue
# At GRUB, press 'e' to edit the kernel line
# Add 'nomodeset' to the linux line
# Press F10 to boot

# Once booted, fix GPU drivers:
# For NVIDIA:
pacman -S nvidia-dkms
mkinitcpio -P
```

### Network Issues

```bash
# Check NetworkManager
rc-service NetworkManager status

# If failed, restart
rc-service NetworkManager restart

# Manual connection
nmcli device status
nmcli connection show
nmcli device wifi list
nmcli device wifi connect "SSID" password "password"
```

### Kernel Panic / Initramfs Issues

```bash
# In chroot, regenerate all initramfs
mkinitcpio -P

# Or reinstall kernels entirely
pacman -S linux linux-lts linux-zen
mkinitcpio -P
```

### Secure Boot Failure

```bash
# Option 1: Disable Secure Boot in BIOS/UEFI settings

# Option 2: Re-sign in chroot
artix-chroot /mnt
sbctl sign-all
sbctl verify
exit

# Option 3: Reset sbctl, then disable Secure Boot
sbctl reset
```

### Emergency Shell

```bash
# If dropped to emergency shell:

# Check what failed (OpenRC)
rc-status --crashed

# Disable problematic service
rc-update del problem-service

# Continue boot
exit
```

### Btrfs Corruption

```bash
# If system is bootable:
sudo btrfs scrub start /
sudo btrfs scrub status /
sudo btrfs device stats /

# If NOT bootable (from Arch ISO):
cryptsetup open /dev/sdX3 cryptroot
mount /dev/mapper/cryptroot /mnt
btrfs scrub start -B /mnt
btrfs device stats /mnt

# For severe corruption:
btrfs check --readonly /dev/mapper/cryptroot
```

---

## Snapshot Rollback

```bash
# Option 1: From GRUB
# Select "Snapshots" submenu, choose a known-good snapshot

# Option 2: Manual rollback
mount /dev/mapper/cryptroot /mnt
snapper -c root list
# Find good snapshot number (e.g., 42)
snapper -c root undochange 42..0

# Option 3: Replace root subvolume
mount /dev/mapper/cryptroot /mnt
mv /mnt/@ /mnt/@.broken
btrfs subvolume snapshot /mnt/@snapshots/42/snapshot /mnt/@
reboot
```

---

## Emergency Quick Reference Card

```
┌────────────────────────────────────────────────────────────────────┐
│                    LogOS EMERGENCY RECOVERY                        │
├────────────────────────────────────────────────────────────────────┤
│ 1. Boot Arch Linux USB                                             │
│ 2. cryptsetup open /dev/sdX3 cryptroot                            │
│ 3. mount -o subvol=@ /dev/mapper/cryptroot /mnt                   │
│ 4. mount /dev/sdX2 /mnt/boot                                      │
│ 5. mount /dev/sdX1 /mnt/boot/efi                                  │
│ 6. artix-chroot /mnt                                               │
│ 7. [Fix the problem]                                              │
│ 8. exit                                                            │
│ 9. umount -R /mnt                                                 │
│ 10. reboot                                                         │
└────────────────────────────────────────────────────────────────────┘
```
