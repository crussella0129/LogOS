# LogOS Installer-Proto

This is a hardened, interactive installer entrypoint that preserves the same
features as the current LogOS installer (GPU selection, secure boot, and desktop
environment choice) while providing a safer command-driven interface.

It reuses the existing modules in `installer/` and should be run from the LogOS
repo root.

## Launch

```bash
cd LogOS/installer
chmod +x logos-install.sh
sudo ./logos-install.sh
```

## Commands

```bash
./logos-install.sh run
```
Start a full install (default). Prompts for disk, user info, GPU, GUI, and
secure boot, then runs the full install pipeline.

```bash
./logos-install.sh resume
```
Resume an install using the last saved config at `/tmp/logos-install.conf`.

```bash
./logos-install.sh config
```
Collect and save configuration only (no disk changes).

```bash
./logos-install.sh validate
```
Run pre-flight checks only (UEFI, network, required tools, etc.).

```bash
./logos-install.sh logs
```
Show install log locations.

```bash
./logos-install.sh help
```
Show help text.

## Notes

- Requires an Arch Linux live environment and UEFI boot mode.
- The installer expects internet connectivity for package downloads.
- Config file: `/tmp/logos-install.conf`
- Logs: `/tmp/logos-install.log` and `/tmp/logos-install-verbose.log`
