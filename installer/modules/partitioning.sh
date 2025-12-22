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

    success "Partitions created: $EFI_PART, $BOOT_PART, $ROOT_PART"
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

    # Format EFI partition
    log "Formatting EFI partition (FAT32)..."
    mkfs.fat -F32 -n EFI "$EFI_PART" &>/dev/null

    # Format boot partition
    log "Formatting boot partition (ext4)..."
    mkfs.ext4 -L BOOT "$BOOT_PART" &>/dev/null

    # Create Btrfs on encrypted root
    log "Creating Btrfs filesystem on encrypted partition..."
    mkfs.btrfs -f -L LogOS /dev/mapper/cryptroot &>/dev/null

    success "Filesystems created"

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

    # Create mount points
    mkdir -p /mnt/{boot,boot/efi,home,.snapshots,var/log,var/cache}

    # Mount boot
    mount "$BOOT_PART" /mnt/boot

    # Mount EFI
    mount "$EFI_PART" /mnt/boot/efi

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

    # Verify mounts
    log "Verifying mount points..."
    if ! is_mounted /mnt; then
        error "Root filesystem not mounted"
        exit 1
    fi

    success "All filesystems mounted successfully"
}

generate_fstab() {
    log "Generating fstab..."

    # Generate basic fstab
    genfstab -U /mnt >> /mnt/etc/fstab

    # Get Btrfs UUID
    local btrfs_uuid=$(get_btrfs_uuid)

    # Add Cold Canon subvolume (with copies=2 for bitrot protection)
    mkdir -p /mnt/home/"$USERNAME"/Documents
    cat >> /mnt/etc/fstab <<EOF

# Cold Canon (copies=2 for bitrot protection)
UUID=$btrfs_uuid  /home/$USERNAME/Documents  btrfs  subvol=@canon,noatime,compress=zstd:9,space_cache=v2,discard=async,copies=2  0  0

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
