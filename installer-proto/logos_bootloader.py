"""
LogOS Ringed City Bootloader Plugin for archinstall

This plugin overrides the default GRUB configuration to install
Ringed City triple-kernel boot profiles.
"""

from pathlib import Path
import subprocess

from archinstall import info, debug, warn
from archinstall.lib.installer import Installer


def on_add_bootloader(installation: Installer) -> bool:
    """
    Called by archinstall when adding a bootloader.
    Return True if handled here, False to fall back to default.
    """
    info("LogOS: installing Ringed City boot profiles...")

    try:
        _install_kernel_trio(installation)
        _install_grub(installation)
        _create_ringed_city_profiles(installation)
        _regenerate_grub(installation)
        info("LogOS: Ringed City boot profiles installed.")
        return True
    except Exception as exc:
        warn(f"LogOS plugin failed: {exc}")
        warn("Falling back to default bootloader installation.")
        return False


def _install_kernel_trio(installation: Installer) -> None:
    info("LogOS: installing kernel trio...")
    kernels = [
        "linux", "linux-headers",
        "linux-lts", "linux-lts-headers",
        "linux-zen", "linux-zen-headers",
    ]
    installation.pacman.strap(*kernels)
    installation.pacman.strap("apparmor", "audit")


def _install_grub(installation: Installer) -> None:
    info("LogOS: installing GRUB...")
    installation.pacman.strap("grub", "efibootmgr", "os-prober")

    efi_partition = installation._get_efi_partition()
    efi_mount = efi_partition.mountpoint if efi_partition else "/boot/efi"

    installation.arch_chroot(
        "grub-install --target=x86_64-efi "
        f"--efi-directory={efi_mount} "
        "--bootloader-id=LogOS --recheck"
    )


def _create_ringed_city_profiles(installation: Installer) -> None:
    info("LogOS: creating Ringed City profiles...")

    target = installation.target

    crypt_uuid = _get_crypt_uuid(installation)
    btrfs_uuid = _get_btrfs_uuid(installation)

    if not crypt_uuid or not btrfs_uuid:
        raise ValueError("Could not determine disk UUIDs")

    debug(f"CRYPT_UUID: {crypt_uuid}")
    debug(f"BTRFS_UUID: {btrfs_uuid}")

    grub_default = """\
# LogOS GRUB Configuration
GRUB_DEFAULT=saved
GRUB_SAVEDEFAULT=true
GRUB_TIMEOUT=10
GRUB_DISTRIBUTOR=\"LogOS\"
GRUB_CMDLINE_LINUX_DEFAULT=\"\"
GRUB_CMDLINE_LINUX=\"\"
GRUB_ENABLE_CRYPTODISK=y
GRUB_DISABLE_OS_PROBER=false
GRUB_GFXMODE=auto
GRUB_GFXPAYLOAD_LINUX=keep
GRUB_TERMINAL_OUTPUT=gfxterm
"""

    grub_default_path = Path(target) / "etc/default/grub"
    grub_default_path.write_text(grub_default)

    crypt_uuid_nodash = crypt_uuid.replace("-", "")

    profiles_script = f"""\
#!/bin/bash
cat << 'MENUEOF'
# LogOS Ringed City Security Profiles

# GAEL PROFILE - Maximum Security
menuentry "LogOS - Gael [Maximum Security]" --class logos --class gnu-linux --class gnu --class os $menuentry_id_option 'logos-gael' {{
    load_video
    set gfxpayload=keep
    insmod gzio
    insmod part_gpt
    insmod btrfs
    insmod cryptodisk
    insmod luks2
    cryptomount -u {crypt_uuid_nodash}
    search --no-floppy --fs-uuid --set=root {btrfs_uuid}
    echo 'Loading Linux LTS with Maximum Security...'
    linux /@/boot/vmlinuz-linux-lts root=UUID={btrfs_uuid} rootflags=subvol=@ rw \
        cryptdevice=UUID={crypt_uuid}:cryptroot \
        audit=1 apparmor=1 \
        lsm=landlock,lockdown,yama,integrity,apparmor,bpf \
        lockdown=confidentiality \
        mitigations=auto,nosmt nosmt=force \
        init_on_alloc=1 init_on_free=1 slab_nomerge pti=on \
        quiet loglevel=3
    echo 'Loading initial ramdisk...'
    initrd /@/boot/initramfs-linux-lts.img
}}

# MIDIR PROFILE - Balanced Daily Driver
menuentry "LogOS - Midir [Daily Driver]" --class logos --class gnu-linux --class gnu --class os $menuentry_id_option 'logos-midir' {{
    load_video
    set gfxpayload=keep
    insmod gzio
    insmod part_gpt
    insmod btrfs
    insmod cryptodisk
    insmod luks2
    cryptomount -u {crypt_uuid_nodash}
    search --no-floppy --fs-uuid --set=root {btrfs_uuid}
    echo 'Loading Linux Zen - Daily Driver...'
    linux /@/boot/vmlinuz-linux-zen root=UUID={btrfs_uuid} rootflags=subvol=@ rw \
        cryptdevice=UUID={crypt_uuid}:cryptroot \
        audit=1 apparmor=1 \
        lsm=landlock,lockdown,yama,integrity,apparmor,bpf \
        mitigations=auto \
        quiet loglevel=3
    echo 'Loading initial ramdisk...'
    initrd /@/boot/initramfs-linux-zen.img
}}

# HALFLIGHT PROFILE - Maximum Performance
menuentry "LogOS - Halflight [Performance]" --class logos --class gnu-linux --class gnu --class os $menuentry_id_option 'logos-halflight' {{
    load_video
    set gfxpayload=keep
    insmod gzio
    insmod part_gpt
    insmod btrfs
    insmod cryptodisk
    insmod luks2
    cryptomount -u {crypt_uuid_nodash}
    search --no-floppy --fs-uuid --set=root {btrfs_uuid}
    echo 'Loading Linux Zen - Performance Mode...'
    linux /@/boot/vmlinuz-linux-zen root=UUID={btrfs_uuid} rootflags=subvol=@ rw \
        cryptdevice=UUID={crypt_uuid}:cryptroot \
        audit=0 mitigations=off \
        nowatchdog nmi_watchdog=0 \
        quiet loglevel=3
    echo 'Loading initial ramdisk...'
    initrd /@/boot/initramfs-linux-zen.img
}}

# Recovery submenu
submenu "LogOS Recovery Options" --class recovery {{
    menuentry "Linux LTS - Fallback Initramfs" --class recovery {{
        load_video
        insmod gzio
        insmod part_gpt
        insmod btrfs
        insmod cryptodisk
        insmod luks2
        cryptomount -u {crypt_uuid_nodash}
        search --no-floppy --fs-uuid --set=root {btrfs_uuid}
        linux /@/boot/vmlinuz-linux-lts root=UUID={btrfs_uuid} rootflags=subvol=@ rw \
            cryptdevice=UUID={crypt_uuid}:cryptroot
        initrd /@/boot/initramfs-linux-lts-fallback.img
    }}

    menuentry "Linux (Mainline) - Fallback" --class recovery {{
        load_video
        insmod gzio
        insmod part_gpt
        insmod btrfs
        insmod cryptodisk
        insmod luks2
        cryptomount -u {crypt_uuid_nodash}
        search --no-floppy --fs-uuid --set=root {btrfs_uuid}
        linux /@/boot/vmlinuz-linux root=UUID={btrfs_uuid} rootflags=subvol=@ rw \
            cryptdevice=UUID={crypt_uuid}:cryptroot
        initrd /@/boot/initramfs-linux-fallback.img
    }}
}}
MENUEOF
"""

    profiles_path = Path(target) / "etc/grub.d/41_logos_profiles"
    profiles_path.write_text(profiles_script)
    profiles_path.chmod(0o755)

    default_linux = Path(target) / "etc/grub.d/10_linux"
    if default_linux.exists():
        default_linux.chmod(0o644)


def _regenerate_grub(installation: Installer) -> None:
    info("LogOS: regenerating initramfs and GRUB config...")
    installation.arch_chroot("mkinitcpio -P")
    installation.arch_chroot("grub-mkconfig -o /boot/grub/grub.cfg")


def _get_crypt_uuid(installation: Installer) -> str:
    result = subprocess.run(
        ["blkid", "-t", "TYPE=crypto_LUKS", "-s", "UUID", "-o", "value"],
        capture_output=True, text=True
    )
    if result.returncode == 0 and result.stdout.strip():
        return result.stdout.strip().split("\n")[0]

    for partition in getattr(installation, "partitions", []):
        if getattr(partition, "encrypted", False):
            return partition.uuid

    return ""


def _get_btrfs_uuid(installation: Installer) -> str:
    result = subprocess.run(
        ["blkid", "-s", "UUID", "-o", "value", "/dev/mapper/cryptroot"],
        capture_output=True, text=True
    )
    if result.returncode == 0 and result.stdout.strip():
        return result.stdout.strip()

    for pattern in ["/dev/mapper/luks-*", "/dev/mapper/arch*"]:
        import glob
        for dev in glob.glob(pattern):
            result = subprocess.run(
                ["blkid", "-s", "UUID", "-o", "value", dev],
                capture_output=True, text=True
            )
            if result.returncode == 0 and result.stdout.strip():
                return result.stdout.strip()

    return ""
