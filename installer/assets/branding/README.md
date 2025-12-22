# LogOS Branding Assets

This directory contains the official LogOS branding assets used throughout the operating system.

## Files

### `logos-boot.png`
- **Purpose**: GRUB bootloader splash screen
- **Resolution**: 1536x1024 (3:2 aspect ratio)
- **Used by**: `modules/bootloader.sh`
- **Installation location**: `/boot/grub/themes/logos/logos-boot.png`
- **Description**: Displayed during boot when selecting the Ringed City profile (Gael, Midir, or Halflight)

### `logos-wallpaper.png`
- **Purpose**: Default desktop wallpaper
- **Resolution**: 1536x1024 (3:2 aspect ratio, scales to any display)
- **Used by**: `modules/tier2-standalone.sh`
- **Installation locations**:
  - `/usr/share/backgrounds/logos/logos-wallpaper.png` (system-wide)
  - `~/Pictures/Wallpapers/logos-wallpaper.png` (user directory)
- **Description**: Set as default wallpaper for all supported desktop environments

## Supported Desktop Environments

The wallpaper is automatically configured for:
- **GNOME**: Set via gsettings (both light and dark themes)
- **KDE Plasma**: Set via KDE wallpaper script
- **XFCE**: Set via xfconf-query
- **i3-wm**: Set via feh on startup

## Design Specifications

### Color Scheme
- **Background**: Dark grey/charcoal (#2b2b2b)
- **Logo**: White/cream (#f0f0f0)
- **Style**: Minimalist, professional, clean

### Logo Elements
- Triangular symbol representing the Ringed City architecture
- "LogOS" text in clean sans-serif font
- Centered composition for universal compatibility

## Usage During Installation

1. **Boot Phase**: `logos-boot.png` is copied to `/boot/grub/themes/logos/` during bootloader installation
2. **Desktop Phase**: `logos-wallpaper.png` is copied to system directories during Tier 2 installation
3. **Automatic Configuration**: Desktop environment wallpaper settings are updated automatically

## Customization

To replace the default branding:

1. Replace `logos-boot.png` and/or `logos-wallpaper.png` with your custom images
2. Keep the same filenames
3. Recommended resolutions:
   - Boot: 1920x1080 or 1024x768 (GRUB supports various resolutions)
   - Wallpaper: 1920x1080 minimum (higher for 4K displays)
4. Supported formats: PNG (GRUB requires PNG for boot images)

## License

LogOS branding assets are part of the LogOS project.

---

*LogOS - Ontology Substrate Operating System*
