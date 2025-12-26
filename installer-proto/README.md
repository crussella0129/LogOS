# LogOS archinstall installer-proto (Not Yet Validated)

This folder contains a prototype archinstall custom profile + plugin that injects the
Ringed City GRUB selector into the install process.

## Contents

- `logos_bootloader.py`: archinstall plugin that overrides bootloader setup and writes
  Ringed City GRUB profiles.
- `logos_profile.py`: custom archinstall profile that installs LogOS packages and enables
  baseline services.

## Quick start (on Arch ISO)

1) Copy the plugin and profile to archinstall config paths:

```
mkdir -p ~/.config/archinstall/{plugins,profiles}
cp /path/to/repo/installer-proto/logos_bootloader.py ~/.config/archinstall/plugins/
cp /path/to/repo/installer-proto/logos_profile.py ~/.config/archinstall/profiles/logos.py
```

2) Run archinstall and select the profile:

```
archinstall
```

- Choose the "LogOS" profile when prompted.
- The plugin will intercept bootloader setup to create the Ringed City GRUB menu.

## Notes

- The plugin installs the kernel trio and GRUB, then writes `/etc/grub.d/41_logos_profiles`
  and regenerates GRUB.
- If the plugin fails, archinstall falls back to default bootloader logic.
- UUID detection attempts to locate LUKS and Btrfs devices; adjust the helpers if your
  layout differs.

## Testing

After install, verify:

```
ls /boot/vmlinuz-*
grep "LogOS" /boot/grub/grub.cfg
cat /etc/grub.d/41_logos_profiles
```
