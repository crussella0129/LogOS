#!/usr/bin/env bash
# LogOS Gentoo — Phase 0 Test Harness
# Tests partitioning, LUKS2, and Btrfs subvolume creation against a qcow2 disk via NBD
# Usage: sudo ./test-phase0.sh
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QCOW2="${TEST_DIR}/logos-test.qcow2"
NBD_DEV="/dev/nbd0"
LUKS_PASS="REDACTED_PASS"
PASS=0; FAIL=0

pass() { echo -e "\e[32m  PASS: $*\e[0m"; ((PASS++)) || true; }
fail() { echo -e "\e[31m  FAIL: $*\e[0m"; ((FAIL++)) || true; }

cleanup() {
  echo ""; echo "== Cleaning up =="
  umount -R /mnt/logos-test 2>/dev/null || true
  cryptsetup close logos-test-crypt 2>/dev/null || true
  sleep 1
  qemu-nbd --disconnect "${NBD_DEV}" 2>/dev/null || true
  rm -rf /mnt/logos-test 2>/dev/null || true
  echo "Done."
}
trap cleanup EXIT

[[ "${EUID}" -eq 0 ]] || { echo "Run as root"; exit 1; }

# Reset disk
qemu-img create -f qcow2 "${QCOW2}" 30G >/dev/null 2>&1 || true

# NBD
echo ""; echo "== NBD Connection =="
modprobe nbd max_part=8 2>/dev/null || true
qemu-nbd --disconnect "${NBD_DEV}" 2>/dev/null || true
sleep 1
qemu-nbd --connect="${NBD_DEV}" "${QCOW2}"
sleep 2
[[ -b "${NBD_DEV}" ]] && pass "NBD connected" || { fail "NBD failed"; exit 1; }

# Partition
echo ""; echo "== Partitioning =="
sgdisk --zap-all "${NBD_DEV}" >/dev/null 2>&1 || true
sgdisk --new=1:0:+1G --typecode=1:ef00 --change-name=1:"EFI"  "${NBD_DEV}" >/dev/null
sgdisk --new=2:0:+4G --typecode=2:8300 --change-name=2:"Boot" "${NBD_DEV}" >/dev/null
sgdisk --new=3:0:0   --typecode=3:8309 --change-name=3:"Root" "${NBD_DEV}" >/dev/null
partprobe "${NBD_DEV}" 2>/dev/null || true
sleep 2

[[ -b "${NBD_DEV}p1" ]] && pass "EFI partition (p1)" || fail "EFI missing"
[[ -b "${NBD_DEV}p2" ]] && pass "Boot partition (p2)" || fail "Boot missing"
[[ -b "${NBD_DEV}p3" ]] && pass "Root partition (p3)" || fail "Root missing"

PART_INFO="$(sgdisk -p "${NBD_DEV}" 2>/dev/null)"
echo "${PART_INFO}" | grep -q "EF00" && pass "EFI type EF00" || fail "EFI wrong type"
echo "${PART_INFO}" | grep -q "8309" && pass "Root type 8309" || fail "Root wrong type"

# Format EFI + Boot
echo ""; echo "== Filesystem Formatting =="
mkfs.fat -F32 -n EFI "${NBD_DEV}p1" >/dev/null 2>&1
blkid "${NBD_DEV}p1" | grep -q "vfat" && pass "EFI: FAT32" || fail "EFI format failed"

mkfs.ext4 -F -L boot "${NBD_DEV}p2" >/dev/null 2>&1
blkid "${NBD_DEV}p2" | grep -q "ext4" && pass "Boot: ext4" || fail "Boot format failed"

# LUKS2
echo ""; echo "== LUKS2 Encryption =="
echo -n "${LUKS_PASS}" | cryptsetup luksFormat \
  --type luks2 --cipher aes-xts-plain64 --key-size 512 \
  --hash sha512 --pbkdf argon2id --iter-time 2000 \
  --batch-mode "${NBD_DEV}p3" -

cryptsetup isLuks "${NBD_DEV}p3" && pass "LUKS2 created" || { fail "LUKS2 failed"; exit 1; }

LUKS_INFO="$(cryptsetup luksDump "${NBD_DEV}p3" 2>/dev/null)"
echo "${LUKS_INFO}" | grep -q "luks2"           && pass "Version: LUKS2"          || fail "Not LUKS2"
echo "${LUKS_INFO}" | grep -q "aes-xts-plain64" && pass "Cipher: aes-xts-plain64" || fail "Wrong cipher"
echo "${LUKS_INFO}" | grep -qi "argon2"          && pass "PBKDF: argon2"           || fail "Wrong PBKDF"
echo "${LUKS_INFO}" | grep -q "512 bits"         && pass "Key: 512 bits"           || fail "Wrong key size"

echo -n "${LUKS_PASS}" | cryptsetup open "${NBD_DEV}p3" logos-test-crypt -
[[ -b /dev/mapper/logos-test-crypt ]] && pass "LUKS opened" || { fail "LUKS open failed"; exit 1; }

# Btrfs + Subvolumes
echo ""; echo "== Btrfs + Subvolumes =="
mkfs.btrfs -f -L LogOS /dev/mapper/logos-test-crypt >/dev/null 2>&1
blkid /dev/mapper/logos-test-crypt | grep -q "btrfs" && pass "Btrfs created" || { fail "Btrfs failed"; exit 1; }

mkdir -p /mnt/logos-test
mount /dev/mapper/logos-test-crypt /mnt/logos-test

for sv in @ @home @canon @mesh @snapshots @log; do
  btrfs subvolume create "/mnt/logos-test/${sv}" >/dev/null
  btrfs subvolume show "/mnt/logos-test/${sv}" >/dev/null 2>&1 \
    && pass "Subvolume: ${sv}" || fail "Subvolume ${sv} failed"
done

umount /mnt/logos-test

# Mount hierarchy
echo ""; echo "== Mount Hierarchy =="
BTRFS_OPTS="noatime,compress=zstd:3,space_cache=v2"
mount -o "subvol=@,${BTRFS_OPTS}" /dev/mapper/logos-test-crypt /mnt/logos-test
mkdir -p /mnt/logos-test/{home,srv/cold-canon,srv/warm-mesh,var/log,.snapshots,boot,boot/efi}

mount -o "subvol=@home,${BTRFS_OPTS}"      /dev/mapper/logos-test-crypt /mnt/logos-test/home
mount -o "subvol=@canon,${BTRFS_OPTS}"     /dev/mapper/logos-test-crypt /mnt/logos-test/srv/cold-canon
mount -o "subvol=@mesh,${BTRFS_OPTS}"      /dev/mapper/logos-test-crypt /mnt/logos-test/srv/warm-mesh
mount -o "subvol=@snapshots,${BTRFS_OPTS}" /dev/mapper/logos-test-crypt /mnt/logos-test/.snapshots
mount -o "subvol=@log,${BTRFS_OPTS}" /dev/mapper/logos-test-crypt /mnt/logos-test/var/log
chattr +C /mnt/logos-test/var/log
mount "${NBD_DEV}p2" /mnt/logos-test/boot
mkdir -p /mnt/logos-test/boot/efi
mount "${NBD_DEV}p1" /mnt/logos-test/boot/efi

for mp in / /home /srv/cold-canon /srv/warm-mesh /.snapshots /var/log /boot /boot/efi; do
  mountpoint -q "/mnt/logos-test${mp}" 2>/dev/null && pass "Mounted: ${mp}" || fail "Not mounted: ${mp}"
done

ROOT_OPTS="$(findmnt -n -o OPTIONS /mnt/logos-test)"
echo "${ROOT_OPTS}" | grep -q "compress=zstd:3" && pass "Compression: zstd:3" || fail "Compression wrong"

LOG_ATTRS="$(lsattr -d /mnt/logos-test/var/log 2>/dev/null || echo "")"
echo "${LOG_ATTRS}" | grep -q "C" && pass "Log: nodatacow (chattr +C)" || fail "Log missing nodatacow"

# UUIDs
echo ""; echo "== UUID Capture =="
CRYPT_UUID="$(blkid -s UUID -o value "${NBD_DEV}p3")"
BTRFS_UUID="$(blkid -s UUID -o value /dev/mapper/logos-test-crypt)"
BOOT_UUID="$(blkid -s UUID -o value "${NBD_DEV}p2")"
EFI_UUID="$(blkid -s UUID -o value "${NBD_DEV}p1")"

[[ -n "${CRYPT_UUID}" ]] && pass "CRYPT_UUID: ${CRYPT_UUID}" || fail "CRYPT_UUID empty"
[[ -n "${BTRFS_UUID}" ]] && pass "BTRFS_UUID: ${BTRFS_UUID}" || fail "BTRFS_UUID empty"
[[ -n "${BOOT_UUID}" ]]  && pass "BOOT_UUID:  ${BOOT_UUID}"  || fail "BOOT_UUID empty"
[[ -n "${EFI_UUID}" ]]   && pass "EFI_UUID:   ${EFI_UUID}"   || fail "EFI_UUID empty"

mkdir -p /mnt/logos-test/tmp
cat > /mnt/logos-test/tmp/logos-uuids << UEOF
CRYPT_UUID="${CRYPT_UUID}"
BTRFS_UUID="${BTRFS_UUID}"
BOOT_UUID="${BOOT_UUID}"
EFI_UUID="${EFI_UUID}"
UEOF
pass "UUIDs saved"

# Summary
echo ""
echo "========================================"
echo "  Phase 0 Test Results"
echo "  PASS: ${PASS}  FAIL: ${FAIL}"
echo "========================================"

cat > "${TEST_DIR}/test-phase0-results.log" << REOF
Phase 0 Test — $(date -Iseconds)
PASS: ${PASS}
FAIL: ${FAIL}
CRYPT_UUID: ${CRYPT_UUID}
BTRFS_UUID: ${BTRFS_UUID}
BOOT_UUID: ${BOOT_UUID}
EFI_UUID: ${EFI_UUID}
Partitions: EFI(1GB FAT32) + Boot(4GB ext4) + Root(LUKS2->Btrfs)
Subvolumes: @ @home @canon @mesh @snapshots @log
Encryption: LUKS2 aes-xts-plain64 512-bit argon2id
REOF

[[ "${FAIL}" -gt 0 ]] && exit 1 || exit 0
