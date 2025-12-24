#!/bin/bash

################################################################################
# LogOS Installer - Disk Partitioning Module
################################################################################

prepare_disk() {
    log "Preparing disk $DISK for installation..."

    # Get partition names based on disk type
    get_partition_names "$DISK"

    # Warn about data loss
    warning "All data on $DISK will be erased!"
    sleep 3
}

create_partitions() {
    log "Creating partition table on $DISK..."

    # Wipe existing partition table and data
    wipefs -af "$DISK" &>/dev/null || true
    sgdisk --zap-all "$DISK" &>/dev/null || true
    dd if=/dev/zero of="$DISK" bs=1M count=100 &>/dev/null || true
    partprobe "$DISK"
    sleep 2

    # Create GPT partition table
    log "Creating GPT partition table..."
    parted -s "$DISK" mklabel gpt

    # Create partitions
    log "Creating EFI partition (1GB)..."
    parted -s "$DISK" mkpart primary fat32 1MiB 1025MiB
    parted -s "$DISK" set 1 esp on

    log "Creating boot partition (4GB)..."
    parted -s "$DISK" mkpart primary ext4 1025MiB 5121MiB

    log "Creating root partition (remaining space)..."
    parted -s "$DISK" mkpart primary 5121MiB 100%

    # Inform kernel of partition changes
    partprobe "$DISK"
    sleep 2

    # Get partition names
    get_partition_names "$DISK"

    # Verify partitions were actually created
    log "Verifying partition creation..."

    for part in "$EFI_PART" "$BOOT_PART" "$ROOT_PART"; do
        if [[ ! -b "$part" ]]; then
            error "Partition not created: $part"
            log "Available block devices:"
            lsblk -o NAME,TYPE,SIZE,FSTYPE
            return 1
        fi
    done

    success "All partitions created successfully"
    success "Partition names: $EFI_PART, $BOOT_PART, $ROOT_PART"
}

setup_encryption() {
    log "Setting up LUKS2 encryption on $ROOT_PART..."

    # Create LUKS container
    echo -n "$LUKS_PASS" | cryptsetup luksFormat \
        --type luks2 \
        --cipher aes-xts-plain64 \
        --key-size 512 \
        --hash sha512 \
        --pbkdf argon2id \
        --iter-time 3000 \
        --use-random \
        "$ROOT_PART" -

    success "LUKS encryption configured"

    # Open encrypted partition
    log "Opening encrypted partition..."
    echo -n "$LUKS_PASS" | cryptsetup open "$ROOT_PART" cryptroot -

    # Verify
    if [[ ! -b /dev/mapper/cryptroot ]]; then
        error "Failed to open encrypted partition"
        exit 1
    fi

    success "Encrypted partition opened as /dev/mapper/cryptroot"
}

mount_filesystems() {
    log "Creating filesystems..."

    # Ensure vfat kernel module is loaded
    log "Loading vfat kernel module..."
    if ! modprobe vfat >> "$INSTALL_LOG" 2>&1; then
        warning "vfat module already loaded or built-in"
    fi

    # Format EFI partition
    log "Formatting EFI partition (FAT32)..."
    if ! mkfs.fat -F32 -n EFI "$EFI_PART" >> "$INSTALL_LOG" 2>&1; then
        error "Failed to format EFI partition $EFI_PART"
        return 1
    fi

    # Format boot partition
    log "Formatting boot partition (ext4)..."
    if ! mkfs.ext4 -L BOOT "$BOOT_PART" &>/dev/null; then
        error "Failed to format boot partition $BOOT_PART"
        return 1
    fi

    # Create Btrfs on encrypted root
    log "Creating Btrfs filesystem on encrypted partition..."
    if ! mkfs.btrfs -f -L LogOS /dev/mapper/cryptroot &>/dev/null; then
        error "Failed to create Btrfs filesystem"
        return 1
    fi

    success "Filesystems created"

    # Verify filesystems were created successfully
    log "Verifying filesystem creation..."

    if ! blkid "$EFI_PART" | grep -q "vfat"; then
        error "EFI filesystem not created properly"
        return 1
    fi

    if ! blkid "$BOOT_PART" | grep -q "ext4"; then
        error "Boot filesystem not created properly"
        return 1
    fi

    if ! blkid /dev/mapper/cryptroot | grep -q "btrfs"; then
        error "Root filesystem not created properly"
        return 1
    fi

    success "All filesystems verified"

    # Ensure all filesystem changes are written to disk
    log "Synchronizing filesystem changes to disk..."
    sync

    # Refresh kernel partition table to recognize new filesystems
    partprobe "$DISK"

    # Wait for kernel to fully recognize filesystems
    sleep 3

    # Additional wait for udev device node creation
    log "Waiting for device nodes to be created..."
    for i in {1..10}; do
        if [[ -b "$EFI_PART" ]] && [[ -b "$BOOT_PART" ]]; then
            success "Device nodes ready"
            break
        fi
        sleep 0.5
    done

    # Final verification
    if [[ ! -b "$EFI_PART" ]]; then
        error "EFI partition device node still doesn't exist: $EFI_PART"
        lsblk -o NAME,TYPE,SIZE,FSTYPE
        return 1
    fi

    success "Filesystem changes synchronized"

    # Mount root and create subvolumes
    log "Creating Btrfs subvolumes..."
    mount /dev/mapper/cryptroot /mnt

    # Create subvolumes
    btrfs subvolume create /mnt/@ &>/dev/null
    btrfs subvolume create /mnt/@home &>/dev/null
    btrfs subvolume create /mnt/@snapshots &>/dev/null
    btrfs subvolume create /mnt/@canon &>/dev/null
    btrfs subvolume create /mnt/@mesh &>/dev/null
    btrfs subvolume create /mnt/@log &>/dev/null
    btrfs subvolume create /mnt/@cache &>/dev/null

    success "Btrfs subvolumes created"

    # Unmount and remount with proper options
    umount /mnt

    log "Mounting filesystems with optimized options..."

    # Mount root subvolume
    mount -o noatime,compress=zstd:3,space_cache=v2,discard=async,subvol=@ \
        /dev/mapper/cryptroot /mnt

    # Verify root is mounted before creating subdirectories
    if ! mountpoint -q /mnt; then
        error "Root filesystem not mounted at /mnt"
        return 1
    fi
    success "Root filesystem mounted and verified"

    # Create mount points (note: boot/efi is created AFTER mounting boot partition)
    mkdir -p /mnt/{boot,home,.snapshots,var/log,var/cache}

    # Verify mount point directories were created
    log "Verifying mount point directories..."
    for dir in boot home .snapshots var/log var/cache; do
        if [[ ! -d "/mnt/$dir" ]]; then
            error "Failed to create directory: /mnt/$dir"
            return 1
        fi
    done
    success "Mount point directories created and verified"

    # Unmount any pre-existing mounts from failed attempts
    log "Checking for pre-existing mounts..."

    if mountpoint -q /mnt/boot/efi 2>/dev/null; then
        warning "EFI mount point already mounted, unmounting..."
        if ! umount /mnt/boot/efi >> "$INSTALL_LOG" 2>&1; then
            error "Failed to unmount existing EFI mount"
            return 1
        fi
    fi

    if mountpoint -q /mnt/boot 2>/dev/null; then
        warning "Boot mount point already mounted, unmounting..."
        if ! umount /mnt/boot >> "$INSTALL_LOG" 2>&1; then
            error "Failed to unmount existing boot mount"
            return 1
        fi
    fi

    success "Mount points clear"

    # Pre-mount diagnostics and verification
    log "Pre-mount verification for boot partition..."

    # Check device exists
    if [[ ! -b "$BOOT_PART" ]]; then
        error "Boot partition device does not exist: $BOOT_PART"
        log "Available block devices:"
        lsblk -o NAME,TYPE,SIZE,FSTYPE | tee -a "$INSTALL_LOG"
        return 1
    fi

    # Check filesystem with blkid
    boot_fstype=$(blkid -s TYPE -o value "$BOOT_PART" 2>/dev/null)
    if [[ "$boot_fstype" != "ext4" ]]; then
        error "Boot partition has wrong filesystem: expected ext4, got $boot_fstype"
        return 1
    fi

    success "Boot partition ready for mounting"

    # Same for EFI partition
    log "Pre-mount verification for EFI partition..."

    if [[ ! -b "$EFI_PART" ]]; then
        error "EFI partition device does not exist: $EFI_PART"
        log "Available block devices:"
        lsblk -o NAME,TYPE,SIZE,FSTYPE | tee -a "$INSTALL_LOG"
        return 1
    fi

    efi_fstype=$(blkid -s TYPE -o value "$EFI_PART" 2>/dev/null)
    if [[ "$efi_fstype" != "vfat" ]]; then
        error "EFI partition has wrong filesystem: expected vfat, got $efi_fstype"
        return 1
    fi

    success "EFI partition ready for mounting"

    # Mount boot partition
    log "Mounting boot partition to /mnt/boot..."
    if ! mount -t ext4 -v "$BOOT_PART" /mnt/boot >> "$INSTALL_LOG" 2>&1; then
        error "Failed to mount boot partition $BOOT_PART"
        log "Mount debugging information:"
        log "  Device: $BOOT_PART"
        log "  Mount point: /mnt/boot"
        log "  Expected filesystem: ext4"
        log "  Actual filesystem: $(blkid -s TYPE -o value $BOOT_PART)"
        log "  Device status: $(lsblk -o NAME,TYPE,SIZE,FSTYPE $BOOT_PART)"
        log "  Current mounts:"
        mount | grep -E "(boot|efi)" | tee -a "$INSTALL_LOG"
        return 1
    fi
    success "Boot partition mounted"

    # Create EFI mount point on the now-mounted boot partition
    log "Creating EFI mount point on boot partition..."
    mkdir -p /mnt/boot/efi
    if [[ ! -d "/mnt/boot/efi" ]]; then
        error "Failed to create /mnt/boot/efi directory"
        return 1
    fi
    success "EFI mount point created"

    # Mount EFI partition
    log "Mounting EFI partition to /mnt/boot/efi..."
    if ! mount -t vfat -v "$EFI_PART" /mnt/boot/efi >> "$INSTALL_LOG" 2>&1; then
        error "Failed to mount EFI partition $EFI_PART"
        log "Mount debugging information:"
        log "  Device: $EFI_PART"
        log "  Mount point: /mnt/boot/efi"
        log "  Expected filesystem: vfat"
        log "  Actual filesystem: $(blkid -s TYPE -o value $EFI_PART)"
        log "  Device status: $(lsblk -o NAME,TYPE,SIZE,FSTYPE $EFI_PART)"
        log "  Mount point exists: $(test -d /mnt/boot/efi && echo yes || echo no)"
        log "  Current mounts:"
        mount | grep -E "(boot|efi)" | tee -a "$INSTALL_LOG"
        log "  Kernel modules:"
        lsmod | grep -E "(vfat|fat)" | tee -a "$INSTALL_LOG"
        return 1
    fi
    success "EFI partition mounted"

    # Mount other subvolumes
    mount -o noatime,compress=zstd:3,space_cache=v2,discard=async,subvol=@home \
        /dev/mapper/cryptroot /mnt/home

    mount -o noatime,compress=zstd:3,space_cache=v2,discard=async,subvol=@snapshots \
        /dev/mapper/cryptroot /mnt/.snapshots

    mount -o noatime,compress=zstd:1,space_cache=v2,discard=async,subvol=@log \
        /dev/mapper/cryptroot /mnt/var/log

    mount -o noatime,compress=zstd:1,space_cache=v2,discard=async,subvol=@cache \
        /dev/mapper/cryptroot /mnt/var/cache

    success "Filesystems mounted"

    # Verify all critical mounts
    log "Verifying all mount points..."
    local mount_errors=0

    for mount_point in /mnt /mnt/boot /mnt/boot/efi /mnt/home /mnt/.snapshots; do
        if ! mountpoint -q "$mount_point"; then
            error "Mount point verification failed: $mount_point"
            ((mount_errors++))
        else
            success "Verified: $mount_point"
        fi
    done

    if [[ $mount_errors -gt 0 ]]; then
        error "Mount verification failed with $mount_errors error(s)"
        return 1
    fi

    success "All filesystems mounted and verified successfully"
}

generate_fstab() {
    log "Generating fstab..."

    # Generate basic fstab
    genfstab -U /mnt >> /mnt/etc/fstab

    # Get Btrfs UUID
    local btrfs_uuid=$(get_btrfs_uuid)

    # Add Cold Canon subvolume (high compression for archival data)
    mkdir -p /mnt/home/"$USERNAME"/Documents
    cat >> /mnt/etc/fstab <<EOF

# Cold Canon (high compression for archival data)
UUID=$btrfs_uuid  /home/$USERNAME/Documents  btrfs  subvol=@canon,noatime,compress=zstd:9,space_cache=v2,discard=async  0  0

# Warm Mesh (sync directory)
EOF

    mkdir -p /mnt/home/"$USERNAME"/Sync
    cat >> /mnt/etc/fstab <<EOF
UUID=$btrfs_uuid  /home/$USERNAME/Sync  btrfs  subvol=@mesh,noatime,compress=zstd:3,space_cache=v2,discard=async  0  0
EOF

    success "fstab generated"

    # Display fstab
    log "Generated fstab:"
    cat /mnt/etc/fstab | tee -a "$INSTALL_LOG"
}
