#!/usr/bin/env bash
# Step-by-step RAID 5 setup for svr1shaikh
# Your disks: sda, sdb, sdc, sdd (4x 1.8TB WD Blue SA510 SSDs)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}RAID 5 Setup for svr1shaikh${NC}"
echo "=================================================="
echo ""
echo "Your 4x 1.8TB SSDs: sda, sdb, sdc, sdd"
echo "System drive: nvme0n1 (will NOT be touched)"
echo ""
echo "RAID 5 Configuration:"
echo "  - Level: RAID 5 (striped with distributed parity)"
echo "  - Usable capacity: ~5.4TB (75% of 7.2TB total)"
echo "  - Redundancy: Can survive failure of 1 drive"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}" 
   exit 1
fi

# Your disks
DISKS=("/dev/sda" "/dev/sdb" "/dev/sdc" "/dev/sdd")
ARRAY_NAME="data"
ARRAY_DEVICE="/dev/md0"  # Use md0 instead of letting mdadm auto-assign
MOUNT_POINT="/data"

echo -e "${YELLOW}Step 1: Verify these are the correct disks${NC}"
echo "--------------------------------------------------"
echo ""
for disk in "${DISKS[@]}"; do
    if [[ -b "$disk" ]]; then
        SIZE=$(lsblk -b -d -o SIZE -n "$disk" | numfmt --to=iec-i --suffix=B)
        MODEL=$(lsblk -d -o MODEL -n "$disk" 2>/dev/null || echo "Unknown")
        MOUNT=$(lsblk -d -o MOUNTPOINT -n "$disk" 2>/dev/null || echo "")
        FSTYPE=$(lsblk -d -o FSTYPE -n "$disk" 2>/dev/null || echo "")
        
        echo "  $disk"
        echo "    Size: $SIZE"
        echo "    Model: $MODEL"
        if [[ -n "$MOUNT" ]]; then
            echo -e "    ${RED}WARNING: This disk is mounted at $MOUNT${NC}"
        fi
        if [[ -n "$FSTYPE" ]]; then
            echo -e "    ${RED}WARNING: This disk has filesystem: $FSTYPE${NC}"
        fi
        echo ""
    else
        echo -e "${RED}  ERROR: $disk not found!${NC}"
        exit 1
    fi
done

echo -e "${RED}⚠️  WARNING: All data on these 4 disks will be destroyed!${NC}"
echo -e "${BLUE}Your system drive (nvme0n1) will NOT be touched.${NC}"
echo ""
read -p "Type 'YES' to confirm these are the correct disks: " confirm
if [[ "$confirm" != "YES" ]]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo -e "${YELLOW}Step 2: Check for existing partitions${NC}"
echo "--------------------------------------------------"
for disk in "${DISKS[@]}"; do
    PARTITION_COUNT=$(lsblk -l -o NAME,TYPE "$disk" 2>/dev/null | grep -c part || echo "0")
    PARTITION_COUNT=$((PARTITION_COUNT + 0))  # Convert to integer
    if [[ $PARTITION_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}  $disk has $PARTITION_COUNT partition(s)${NC}"
        lsblk -l -o NAME,TYPE,SIZE,MOUNTPOINT "$disk" | grep part || true
    else
        echo -e "${GREEN}  $disk has no partitions${NC}"
    fi
done

echo ""
read -p "Press Enter to continue with RAID setup..."

echo ""
echo -e "${YELLOW}Step 3: Wiping disk signatures${NC}"
echo "--------------------------------------------------"
for disk in "${DISKS[@]}"; do
    echo "  Wiping $disk..."
    wipefs -a "$disk" 2>/dev/null || true
    # Clear partition table
    sgdisk -Z "$disk" 2>/dev/null || dd if=/dev/zero of="$disk" bs=1M count=100 2>/dev/null || true
done

# Refresh kernel's view of partition tables
echo "Refreshing kernel partition table..."
for disk in "${DISKS[@]}"; do
    partprobe "$disk" 2>/dev/null || true
done
sleep 1

echo ""
echo -e "${YELLOW}Step 4: Checking for existing RAID arrays${NC}"
echo "--------------------------------------------------"

# Check if array already exists
if [[ -e "$ARRAY_DEVICE" ]]; then
    echo -e "${YELLOW}Array $ARRAY_DEVICE already exists!${NC}"
    echo "Stopping existing array..."
    mdadm --stop "$ARRAY_DEVICE" 2>/dev/null || true
    mdadm --remove "$ARRAY_DEVICE" 2>/dev/null || true
    echo "✓ Existing array stopped"
fi

# Check if any of the disks are part of other arrays
echo "Checking if disks are in use by other arrays..."
for disk in "${DISKS[@]}"; do
    # Check if disk is part of any RAID array
    if mdadm --examine "$disk" >/dev/null 2>&1; then
        echo -e "${YELLOW}  $disk has RAID metadata${NC}"
        # Try to find which array it belongs to
        ARRAY_INFO=$(mdadm --examine "$disk" 2>/dev/null | grep "ARRAY" || true)
        if [[ -n "$ARRAY_INFO" ]]; then
            echo "    $ARRAY_INFO"
        fi
    fi
done

# Check if disks are mounted
echo "Checking if disks are mounted..."
for disk in "${DISKS[@]}"; do
    MOUNTED=$(lsblk -n -o MOUNTPOINT "$disk" 2>/dev/null | grep -v "^$" || true)
    if [[ -n "$MOUNTED" ]]; then
        echo -e "${RED}  ERROR: $disk is mounted at: $MOUNTED${NC}"
        echo "    Please unmount it first: umount $MOUNTED"
        exit 1
    fi
done

# Stop any arrays that might be using these disks
echo "Stopping any arrays using these disks..."
for disk in "${DISKS[@]}"; do
    # Try to find arrays using this disk
    for md_dev in /dev/md*; do
        if [[ -e "$md_dev" ]]; then
            if mdadm --detail "$md_dev" 2>/dev/null | grep -q "$(basename $disk)"; then
                echo "  Stopping $md_dev (uses $disk)..."
                mdadm --stop "$md_dev" 2>/dev/null || true
            fi
        fi
    done
done

# Clear any existing RAID metadata from disks
echo "Clearing any existing RAID metadata..."
for disk in "${DISKS[@]}"; do
    if mdadm --examine "$disk" >/dev/null 2>&1; then
        echo "  Clearing metadata from $disk..."
        mdadm --zero-superblock "$disk" 2>/dev/null || true
    fi
done

echo ""
echo -e "${YELLOW}Step 5: Creating RAID 5 array${NC}"
echo "--------------------------------------------------"

# Create RAID 5 array
echo "Creating RAID 5 array as $ARRAY_DEVICE (this may take a moment)..."
if ! mdadm --create "$ARRAY_DEVICE" \
    --level=5 \
    --raid-devices=4 \
    --metadata=1.2 \
    --name="$ARRAY_NAME" \
    "${DISKS[@]}"; then
    echo -e "${RED}Failed to create RAID array!${NC}"
    echo "Checking current RAID status:"
    cat /proc/mdstat
    echo ""
    echo "Checking disk status:"
    for disk in "${DISKS[@]}"; do
        echo "  $disk:"
        mdadm --examine "$disk" 2>/dev/null | head -5 || echo "    No RAID metadata"
    done
    exit 1
fi

echo ""
echo -e "${GREEN}✓ RAID array created successfully!${NC}"
echo ""

# Verify the array exists - mdadm sometimes creates numeric names like /dev/md126
if [[ ! -e "$ARRAY_DEVICE" ]]; then
    echo -e "${YELLOW}Warning: $ARRAY_DEVICE not found, checking alternative paths...${NC}"
    # Check if it was created with a different name
    for md_dev in /dev/md/*; do
        if [[ -e "$md_dev" ]]; then
            echo "Found: $md_dev"
            ARRAY_DEVICE="$md_dev"
            break
        fi
    done
    
    # If still not found, check /dev/md[0-9]* (numeric names like md126)
    if [[ ! -e "$ARRAY_DEVICE" ]]; then
        for md_dev in /dev/md[0-9]*; do
            if [[ -e "$md_dev" ]]; then
                # Check if this array uses our disks
                ARRAY_DISKS=$(mdadm --detail "$md_dev" 2>/dev/null | grep -oP '/dev/sd[a-z]' | sort | tr '\n' ' ')
                EXPECTED_DISKS=$(printf '%s\n' "${DISKS[@]}" | sort | tr '\n' ' ')
                if [[ "$ARRAY_DISKS" == "$EXPECTED_DISKS" ]]; then
                    echo "Found array using our disks: $md_dev"
                    ARRAY_DEVICE="$md_dev"
                    break
                fi
            fi
        done
    fi
    
    # Also check by name in metadata
    if [[ ! -e "$ARRAY_DEVICE" ]]; then
        for md_dev in /dev/md[0-9]*; do
            if [[ -e "$md_dev" ]]; then
                ARRAY_INFO=$(mdadm --detail "$md_dev" 2>/dev/null | grep "Name :" || true)
                if echo "$ARRAY_INFO" | grep -q "$ARRAY_NAME"; then
                    echo "Found array with name $ARRAY_NAME: $md_dev"
                    ARRAY_DEVICE="$md_dev"
                    break
                fi
            fi
        done
    fi
    
    if [[ ! -e "$ARRAY_DEVICE" ]]; then
        echo -e "${RED}ERROR: RAID array device not found!${NC}"
        echo "Current RAID status:"
        cat /proc/mdstat
        exit 1
    fi
fi

# Update the device path if we found it with a different name
echo -e "${GREEN}Using RAID device: $ARRAY_DEVICE${NC}"

echo "RAID build is starting in the background..."
echo "You can monitor progress with: watch -n 5 'cat /proc/mdstat'"
echo ""

# Show current status
cat /proc/mdstat
echo ""
echo -e "${GREEN}Using RAID device: $ARRAY_DEVICE${NC}"

echo ""
echo -e "${YELLOW}Step 6: Saving mdadm configuration${NC}"
echo "--------------------------------------------------"
mdadm --detail --scan >> /etc/mdadm.conf
echo "✓ mdadm configuration saved to /etc/mdadm.conf"

echo ""
echo -e "${YELLOW}Step 7: Setting up LUKS encryption${NC}"
echo "--------------------------------------------------"
read -sp "Enter LUKS passphrase for $ARRAY_NAME: " luks_passphrase
echo ""
read -sp "Confirm LUKS passphrase: " luks_passphrase_confirm
echo ""

if [[ "$luks_passphrase" != "$luks_passphrase_confirm" ]]; then
    echo -e "${RED}Passphrases do not match!${NC}"
    exit 1
fi

echo ""
echo "Creating LUKS container..."
echo -n "$luks_passphrase" | cryptsetup luksFormat \
    --type luks2 \
    --label "$ARRAY_NAME" \
    "$ARRAY_DEVICE" -

echo ""
echo "Opening LUKS container..."
echo -n "$luks_passphrase" | cryptsetup open \
    --allow-discards \
    "$ARRAY_DEVICE" "$ARRAY_NAME" -

LUKS_DEVICE="/dev/mapper/${ARRAY_NAME}"

echo ""
echo -e "${YELLOW}Step 8: Formatting filesystem${NC}"
echo "--------------------------------------------------"
echo "Formatting with ext4..."
mkfs.ext4 -L "$ARRAY_NAME" "$LUKS_DEVICE"

echo ""
echo -e "${YELLOW}Step 9: Creating mount point and test mount${NC}"
echo "--------------------------------------------------"
mkdir -p "$MOUNT_POINT"
mkdir -p "${MOUNT_POINT}/fun"

# Test mount
mount "$LUKS_DEVICE" "$MOUNT_POINT"
chmod 755 "$MOUNT_POINT"
chmod 755 "${MOUNT_POINT}/fun"

echo -e "${GREEN}✓ Test mount successful!${NC}"
echo ""
df -h "$MOUNT_POINT"

echo ""
echo -e "${GREEN}=================================================="
echo "Setup Complete!"
echo "==================================================${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo "1. ${BLUE}Monitor RAID build progress:${NC}"
echo "   watch -n 5 'cat /proc/mdstat'"
echo "   (Build will take ~4-8 hours, but array is usable)"
echo ""
echo "2. ${BLUE}Test the setup:${NC}"
echo "   echo 'test' > $MOUNT_POINT/test.txt"
echo "   cat $MOUNT_POINT/test.txt"
echo ""
echo "3. ${BLUE}Update NixOS configuration:${NC}"
echo "   sudo nixos-rebuild switch"
echo ""
echo "4. ${BLUE}After rebuild, wait for RAID build to complete${NC}"
echo "   Check: cat /proc/mdstat"
echo "   Look for [UUUU] and no [recovery] or [resync]"
echo ""
echo "5. ${BLUE}Reboot (after build completes):${NC}"
echo "   sudo reboot"
echo "   (You'll be prompted for LUKS password during boot)"
echo ""
echo -e "${BLUE}Current status:${NC}"
echo "  - RAID array: $ARRAY_DEVICE"
echo "  - Mounted at: $MOUNT_POINT"
echo "  - Usable capacity: ~5.4TB"
echo "  - RAID build: In progress (check /proc/mdstat)"
echo ""

