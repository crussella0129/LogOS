# LogOS Installer Architecture

## Overview

The LogOS installer is a production-grade, modular installation system designed for reliability, maintainability, and extensibility. This document describes the architecture, design decisions, and module structure.

## Design Principles

1. **Modularity**: Each installation phase is an independent, testable module
2. **Fail-Fast**: Errors are caught early with comprehensive validation
3. **Idempotency**: Modules can be re-run safely after failures
4. **Logging**: Comprehensive logging at multiple verbosity levels
5. **Recoverability**: Graceful cleanup on errors with state preservation

## Directory Structure

```
installer/
├── logos-install.sh           # Main orchestrator
├── install-logos.sh           # Legacy entry point (compatibility)
│
├── lib/                       # Core libraries
│   ├── common.sh             # Shared utilities
│   ├── validation.sh         # Input validation
│   ├── logging.sh            # Logging subsystem
│   └── error-handling.sh     # Error handling & cleanup
│
├── modules/                   # Installation modules
│   ├── 00-preflight.sh       # System validation
│   ├── 10-disk-setup.sh      # Partitioning (planned)
│   ├── 20-base-install.sh    # Base system (planned)
│   ├── 30-kernel-profiles.sh # Ringed City profiles (planned)
│   ├── 40-security.sh        # Security hardening (planned)
│   ├── 50-knowledge.sh       # Knowledge topology (planned)
│   ├── 60-desktop.sh         # Desktop environment (planned)
│   ├── 70-finalize.sh        # Cleanup & verification (planned)
│   │
│   └── [legacy modules]      # Existing modules (being migrated)
│       ├── partitioning.sh
│       ├── tier0.sh
│       ├── tier1.sh
│       ├── chroot.sh
│       ├── bootloader.sh
│       ├── tier2-standalone.sh
│       └── tier3-standalone.sh
│
├── profiles/                  # Ringed City configurations
│   ├── gael.conf             # Maximum security profile
│   ├── midir.conf            # Balanced profile
│   └── halflight.conf        # Performance profile
│
├── templates/                 # System configuration templates
│   ├── fstab.template
│   ├── grub.template
│   ├── apparmor/             # AppArmor profiles
│   ├── systemd/              # Systemd units
│   └── grub/                 # GRUB themes
│
├── assets/                    # Installation assets
│   └── branding/
│       ├── logos-boot.png
│       ├── logos-wallpaper.png
│       └── README.md
│
└── README.md                  # Main documentation
```

## Module System

### Numbering Convention

Modules are numbered in execution order:
- **00-09**: Pre-installation (validation, preparation)
- **10-19**: Disk operations (partitioning, encryption)
- **20-29**: Base system installation
- **30-39**: Kernel and boot configuration
- **40-49**: Security hardening
- **50-59**: Knowledge infrastructure
- **60-69**: Desktop environment
- **70-79**: Finalization
- **80-89**: Post-install (optional)
- **90-99**: Validation and testing

### Module Interface

Each module must implement:

```bash
module_XX_name() {
    log_step "XX" "Module Description"

    # Module logic here

    log_success "Module completed"
}

export -f module_XX_name
```

### Module Dependencies

Modules may depend on:
- **Libraries**: `common.sh`, `logging.sh`, `error-handling.sh`, `validation.sh`
- **Configuration**: Variables set by previous modules or user input
- **State**: Files in `/tmp/logos-*` or `/mnt/`

## Library System

### common.sh

Provides shared utilities:
- Progress indicators (`show_progress`, `spinner`)
- Partition detection (`get_partition_names`)
- Chroot execution (`arch_chroot`)
- Package installation (`install_packages`)
- UUID retrieval (`get_uuid`, `get_luks_uuid`)
- Service management (`enable_service`)
- Interactive prompts (`confirm`, `ask_yes_no`)
- System information (`get_total_ram`, `is_laptop`)

### logging.sh

Comprehensive logging system:
- Log levels: `DEBUG`, `INFO`, `WARN`, `ERROR`, `FATAL`
- Dual logging: console + file
- Structured logs: `/tmp/logos-install.log` (user-facing), `/tmp/logos-install-verbose.log` (debug)
- Progress tracking: Step completion, duration
- System diagnostics: Hardware inventory, error context

Functions:
- `log_debug()`, `log_info()`, `log_warn()`, `log_error()`, `log_fatal()`
- `log_step()` - Section headers
- `log_success()` - Success indicators
- `log_cmd()` - Command execution logging
- `start_progress()`, `next_step()`, `complete_step()`

### error-handling.sh

Robust error handling:
- Automatic error trapping
- Stack trace logging
- Cleanup registration
- Safe command execution
- Retry logic
- Assertions

Functions:
- `handle_error()` - Global error handler
- `register_cleanup()` - Register cleanup functions
- `cleanup_on_error()` - Emergency cleanup
- `safe_run()`, `safe_run_critical()` - Safe execution
- `retry_command()` - Retry with backoff
- `assert_*()` - Assertion helpers
- `confirm_destructive()` - Destructive action confirmation

### validation.sh

Input and system validation:
- Disk validation
- Password strength
- Network connectivity
- UEFI mode
- System requirements

Functions:
- `validate_disk()`, `validate_hostname()`, `validate_username()`
- `validate_timezone()`, `validate_locale()`
- `validate_luks_passphrase()`
- `validate_network()`, `validate_uefi()`
- `validate_system_requirements()`

## Profile System

### Profile Structure

Each profile defines:
- Kernel selection (primary + fallback)
- Kernel parameters (security, performance)
- Sysctl parameters (network, kernel, filesystem)
- Security services (AppArmor, audit, firewall)
- Power management
- Module blacklist
- Network configuration

### Profile Selection

Profiles are applied at:
1. **Boot time**: GRUB menu selection (Gael/Midir/Halflight)
2. **Install time**: Default profile configuration
3. **Runtime**: `logos-power` utility for switching

### Profile Files

- `gael.conf`: Maximum security (SMT disabled, full mitigations)
- `midir.conf`: Balanced (recommended for daily use)
- `halflight.conf`: Performance (mitigations off, gaming-optimized)

## Template System

Templates use variable substitution:

```bash
# Template: fstab.template
UUID=__BTRFS_UUID__  /  btrfs  subvol=@,...

# Substitution:
sed -e "s|__BTRFS_UUID__|$btrfs_uuid|g" \
    fstab.template > /mnt/etc/fstab
```

Variables:
- `__EFI_UUID__` - EFI partition UUID
- `__BOOT_UUID__` - Boot partition UUID
- `__CRYPT_UUID__` - LUKS container UUID
- `__BTRFS_UUID__` - Decrypted Btrfs UUID
- `__USERNAME__` - Primary user
- `__HOSTNAME__` - System hostname

## State Management

### Configuration Persistence

User configuration saved to `/tmp/logos-install.conf`:
- Allows installation resume after failure
- Preserves user choices
- Enables unattended installation (via pre-created config)

### Cleanup Registration

Modules register cleanup functions:
```bash
cleanup_disk() {
    umount -R /mnt || true
    cryptsetup close cryptroot || true
}

register_cleanup cleanup_disk
```

Cleanup runs on:
- Normal exit
- Error exit
- Signal interruption (SIGINT, SIGTERM)

## Error Recovery

### Failure Modes

1. **Pre-flight failure**: Exit immediately with error message
2. **Disk operation failure**: Cleanup partitions, close crypto
3. **Package installation failure**: Retry with backoff
4. **Configuration failure**: Log error, continue if non-critical
5. **Bootloader failure**: Critical - abort with detailed diagnostics

### Recovery Procedures

- **Unmount filesystems**: `umount -R /mnt`
- **Close encryption**: `cryptsetup close cryptroot`
- **Preserve logs**: Copy logs before cleanup
- **User notification**: Clear error message + log location

## Testing Strategy

### Unit Testing

Test individual functions:
```bash
./test/test-validation.sh   # Test validation functions
./test/test-logging.sh      # Test logging
```

### Integration Testing

Test module interactions:
```bash
./test/test-disk-setup.sh   # Test partitioning + encryption
./test/test-profiles.sh     # Test profile generation
```

### System Testing

Full installation in VM:
```bash
./test/test-install-vm.sh --profile midir
```

## Logging Levels

Set via `LOGOS_LOG_LEVEL` environment variable:

```bash
LOGOS_LOG_LEVEL=0  # DEBUG (verbose)
LOGOS_LOG_LEVEL=1  # INFO (default)
LOGOS_LOG_LEVEL=2  # WARN
LOGOS_LOG_LEVEL=3  # ERROR
LOGOS_LOG_LEVEL=4  # FATAL
```

## Extension Points

### Adding a New Module

1. Create `modules/XX-name.sh`
2. Implement `module_XX_name()` function
3. Add to `logos-install.sh` module list
4. Update `TOTAL_STEPS` count
5. Document in this file

### Adding a New Profile

1. Create `profiles/name.conf`
2. Define kernel, parameters, services
3. Create GRUB menu entry in `bootloader.sh`
4. Document use cases

### Adding a New Template

1. Create `templates/name.template`
2. Define substitution variables
3. Add substitution logic to relevant module
4. Test with various configurations

## Performance Considerations

- **Parallel operations**: Independent tasks run concurrently
- **Lazy loading**: Modules loaded on-demand
- **Caching**: Mirror list cached, package db synced once
- **Compression**: Btrfs zstd:3 (balanced speed/ratio)
- **I/O optimization**: noatime, async discard

## Security Considerations

- **Sensitive data**: Passwords never logged
- **Config file permissions**: 600 (owner read/write only)
- **Cleanup**: Wipe temp files on exit
- **LUKS security**: Argon2id, 512-bit keys
- **Verification**: Package signatures checked

## Future Enhancements

- [ ] Automated testing in CI/CD
- [ ] Unattended installation mode
- [ ] Network installation (PXE boot)
- [ ] Multi-disk support (RAID, LVM)
- [ ] ARM64 architecture support
- [ ] Graphical installer (TUI with dialog)
- [ ] Post-install validation suite
- [ ] Rollback capability (undo installation)

---

For usage documentation, see [README.md](README.md).
For quick start, see [QUICKSTART.md](QUICKSTART.md).
