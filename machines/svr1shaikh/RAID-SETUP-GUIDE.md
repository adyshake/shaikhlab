# Safe RAID 5 Setup Guide for Running Server

This guide walks you through setting up RAID 5 on a server that's already running, ensuring you don't accidentally wipe important data.

## Prerequisites

- Server is running and accessible
- 4x 2.5TB SSDs are installed but not yet configured
- Root access
- NixOS configuration has been updated (already done)

## Step-by-Step Process

### Step 1: Identify Your Disks

First, identify which disks are your 4x 2.5TB SSDs:

```bash
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,LABEL,MODEL
```

**Look for:**
- Disks that are ~2.5TB in size
- Disks with **NO** mount point (not mounted)
- Disks that are **NOT** your boot drive (`/dev/nvme0n1` or similar)
- Disks that are **NOT** your `/nix` partition

**Example output:**
```
NAME        SIZE TYPE MOUNTPOINT FSTYPE LABEL MODEL
nvme0n1     234G disk            ext4   nix   Samsung SSD
nvme0n1p1   510M part /boot      vfat   boot
nvme0n1p2   234G part            crypto
sdb        2.5T  disk                      Samsung SSD  # <-- This is one
sdc        2.5T  disk                      Samsung SSD  # <-- This is one
sdd        2.5T  disk                      Samsung SSD  # <-- This is one
sde        2.5T  disk                      Samsung SSD  # <-- This is one
```

### Step 2: Verify Disk Details

Double-check each disk to ensure they're the right ones:

```bash
# Check each disk individually
lsblk /dev/sdb
lsblk /dev/sdc
lsblk /dev/sdd
lsblk /dev/sde

# Check if they have any partitions or data
fdisk -l /dev/sdb
fdisk -l /dev/sdc
fdisk -l /dev/sdd
fdisk -l /dev/sde
```

**⚠️ CRITICAL:** Make absolutely sure these are NOT your system disks!

### Step 3: Use the Safe Setup Script

Run the interactive setup script:

```bash
sudo bash machines/svr1shaikh/setup-raid-safe.sh
```

The script will:
1. Show you all disks
2. Ask you to identify the 4 SSDs
3. Show detailed information about each disk
4. Ask for confirmation before proceeding
5. Create the RAID array
6. Set up LUKS encryption
7. Format the filesystem
8. Test mount the array

### Step 4: Monitor RAID Build Progress

After creating the array, monitor the build progress:

```bash
# Watch build progress
watch -n 5 'cat /proc/mdstat'

# Or check periodically
cat /proc/mdstat

# Detailed status
mdadm --detail /dev/md/data
```

**Important:** The RAID build will take several hours (typically 4-8 hours for 2.5TB SSDs). The array is usable during the build, but performance may be reduced.

### Step 5: Test Before Reboot

Before rebooting, test that everything works:

```bash
# Write test data
echo "test" > /data/test.txt
cat /data/test.txt

# Check filesystem
df -h /data

# Unmount and remount to test
umount /data
cryptsetup close data
cryptsetup open /dev/md/data data
mount /dev/mapper/data /data
```

### Step 6: Update NixOS Configuration

Your configuration is already updated, but rebuild to ensure everything is in place:

```bash
# Dry run first (check what will change)
sudo nixos-rebuild dry-run

# If everything looks good, rebuild
sudo nixos-rebuild switch
```

### Step 7: Reboot (After RAID Build Completes)

**⚠️ WAIT:** Don't reboot until the RAID build is complete! Check with:

```bash
cat /proc/mdstat
```

Look for `[UUUU]` (all 4 drives active) and no `[recovery]` or `[resync]` activity.

Once the build is complete:

```bash
sudo reboot
```

During boot:
1. The RAID array will auto-assemble
2. You'll be prompted for the LUKS passphrase for the `data` device
3. The array will mount at `/data`

### Step 8: Verify After Reboot

After reboot, verify everything is working:

```bash
# Check RAID status
cat /proc/mdstat
mdadm --detail /dev/md/data

# Check mount
df -h /data
mount | grep data

# Verify directory structure
ls -la /data/
ls -la /data/fun/
```

## Troubleshooting

### If RAID array doesn't assemble on boot:

```bash
# Manually assemble
mdadm --assemble /dev/md/data

# Check mdadm config
cat /etc/mdadm.conf
```

### If LUKS doesn't prompt for password:

```bash
# Manually unlock
cryptsetup open /dev/md/data data

# Then mount
mount /dev/mapper/data /data
```

### If you need to remove the RAID array:

```bash
# Unmount first
umount /data
cryptsetup close data

# Stop and remove array
mdadm --stop /dev/md/data
mdadm --remove /dev/md/data
```

## Safety Checklist

Before running the setup script, verify:

- [ ] Identified the correct 4 disks (2.5TB SSDs)
- [ ] Verified these disks are NOT mounted
- [ ] Verified these disks are NOT your boot/system drives
- [ ] Backed up any important data (if disks had data)
- [ ] Have the LUKS passphrase ready (write it down securely)
- [ ] Server is accessible via console/IPMI (in case of issues)

## Expected Timeline

- **RAID creation**: ~5-10 minutes
- **RAID build**: ~4-8 hours (background, array is usable)
- **LUKS setup**: ~1 minute
- **Filesystem format**: ~5-10 minutes
- **Total setup time**: ~10-20 minutes (plus background rebuild)

## After Setup

Your `/data` directory structure:
```
/data/              - General data drive (7.5TB usable)
/data/fun/          - Nixarr media directory
/data/nextcloud/    - Nextcloud backups (if enabled)
```

Other applications can create their own directories under `/data` as needed.

