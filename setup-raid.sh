#!/usr/bin/env bash
# Simple RAID 5 setup script for svr1shaikh
# Creates RAID 5 array, LUKS encryption, and ext4 filesystem

set -euo pipefail

DISKS=("/dev/sda" "/dev/sdb" "/dev/sdc" "/dev/sdd")
ARRAY_DEVICE="/dev/md0"
MOUNT_POINT="/data"

if [[ $EUID -ne 0 ]]; then
   echo "Must run as root"
   exit 1
fi

echo "Step 1: Zero RAID superblocks"
for disk in "${DISKS[@]}"; do
    mdadm --zero-superblock "$disk" || true
done

echo "Step 2: Wipe disk signatures"
for disk in "${DISKS[@]}"; do
    wipefs -a "$disk"
    sgdisk -Z "$disk"
done

echo "Step 3: Create RAID 5 array"
mdadm --create "$ARRAY_DEVICE" \
    --level=5 \
    --raid-devices=4 \
    --metadata=1.2 \
    --name=data \
    "${DISKS[@]}"

echo "Step 4: Create LUKS container"
cryptsetup luksFormat --type luks2 --label data "$ARRAY_DEVICE"

echo "Step 5: Open LUKS container"
cryptsetup open --allow-discards "$ARRAY_DEVICE" data

echo "Step 6: Format filesystem"
mkfs.ext4 -L data /dev/mapper/data

echo "Step 7: Mount filesystem"
mkdir -p "$MOUNT_POINT"
mkdir -p "${MOUNT_POINT}/fun"
mount /dev/mapper/data "$MOUNT_POINT"
chmod 755 "$MOUNT_POINT"
chmod 755 "${MOUNT_POINT}/fun"

echo ""
echo "Setup complete!"
df -h "$MOUNT_POINT"
echo ""
echo "=========================================="
echo "RAID array is building. Monitor progress below."
echo "Wait until all devices show [UUUU] before continuing."
echo "DO NOT REBOOT until the RAID build is complete!"
echo "Press Ctrl+C to stop monitoring and continue."
echo "=========================================="
echo ""

# Monitor RAID build progress
trap 'echo ""; echo "Monitoring stopped."; break' INT
while true; do
    clear
    echo "RAID Build Progress (updating every 5 seconds)"
    echo "=========================================="
    cat /proc/mdstat
    echo ""
    echo "Press Ctrl+C to stop monitoring and continue..."
    sleep 5
done
trap - INT

echo ""
read -p "Press Enter to show final mdadm configuration..."

echo ""
echo "=========================================="
echo "Copy this line to hardware-configuration.nix:"
echo "=========================================="
mdadm --detail --scan
