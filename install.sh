#!/usr/bin/env bash

set -e -u -o pipefail

if [ "$(uname)" == "Darwin" ]; then
  # Display warning and wait for confirmation to proceed
  echo "macOS detected"
  echo -e "\n\033[1;31m**Warning:** This script will prepare system for nix-darwin installation.\033[0m"
  read -n 1 -s -r -p "Press any key to continue or Ctrl+C to abort..."

  # inspo: https://forums.developer.apple.com/forums/thread/698954
  echo -e "\n\033[1mInstalling Xcode...\033[0m"
  if [[ -e /Library/Developer/CommandLineTools/usr/bin/git ]]; then
    echo -e "\033[32mXcode already installed.\033[0m"
  else
    # This temporary file prompts the 'softwareupdate' utility to list the Command Line Tools
    touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    PROD=$(softwareupdate -l | grep "\*.*Command Line" | tail -n 1 | sed 's/^[^C]* //')
    softwareupdate -i "$PROD" --verbose
    echo -e "\033[32mXcode installed successfully.\033[0m"
  fi

  echo -e "\n\033[1mInstalling Rosetta...\033[0m"
  softwareupdate --install-rosetta --agree-to-license
  echo -e "\033[32mRosetta installed successfully.\033[0m"

  echo -e "\n\033[1mInstalling Nix...\033[0m"
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm

  # Completed
  echo -e "\n\033[1;32mAll steps completed successfully. nix-darwin is now ready to be installed.\033[0m\n"
  echo -e "To install nix-darwin configuration, run the following commands:\n"
  echo -e "\033[1m. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh\033[0m\n"
  echo -e "\033[1mnix run nix-darwin -- switch --flake github:adyshake/shaikhlab#mac1chng\033[0m\n"
  echo -e "Remember to add the new host public key to sops-nix!"
elif [ "$(uname)" == "Linux" ]; then
  # Check if running as root
  if [ "$EUID" -ne 0 ]; then
    echo -e "\033[1;31mError: This script must be run as root (use sudo)\033[0m"
    echo -e "Run: sudo $0"
    exit 1
  fi

  # Define disks
  OS_DISK="/dev/nvme0n1"
  OS_BOOT_PARTITION="/dev/nvme0n1p1"
  OS_NIX_PARTITION="/dev/nvme0n1p2"
  
  # Data drives for RAID array
  DATA_DRIVES=("/dev/sdb" "/dev/sdc" "/dev/sdd" "/dev/sde")
  RAID_DEVICE="/dev/md0"
  OS_LUKS_DEVICE="cryptroot"
  DATA_LUKS_DEVICE="cryptdata"
  VG_NAME="storage"
  LV_NAME="data"

  # Display warning and wait for confirmation to proceed
  echo "Linux detected"
  echo -e "\n\033[1;31m**Warning:** This script is irreversible and will prepare system for NixOS installation.\033[0m"
  echo -e "\033[1;33m**Setup:** OS on NVMe, Data RAID on 4x 1.8TB drives (sdb, sdc, sdd, sde) with RAID→LUKS→LVM→ext4\033[0m"
  read -n 1 -s -r -p "Press any key to continue or Ctrl+C to abort..."

  # Clear screen before showing disk layout
  clear

  # Display disk layout
  echo -e "\n\033[1mDisk Layout:\033[0m"
  lsblk
  echo ""

  # Undo any previous changes if applicable
  echo -e "\n\033[1mUndoing any previous changes...\033[0m"
  set +e
  umount -R /mnt
  umount -R /mnt/data
  # Remove LVM structures before closing LUKS devices (LVM needs unlocked LUKS devices)
  echo "Removing LVM structures..."
  vgchange -a n $VG_NAME 2>/dev/null || true
  vgremove -f $VG_NAME 2>/dev/null || true
  pvremove -f /dev/mapper/$DATA_LUKS_DEVICE 2>/dev/null || true
  # Now close LUKS devices
  cryptsetup close $OS_LUKS_DEVICE 2>/dev/null || true
  cryptsetup close $DATA_LUKS_DEVICE 2>/dev/null || true
  mdadm --stop $RAID_DEVICE 2>/dev/null || true
  set -e
  echo -e "\033[32mPrevious changes undone.\033[0m"

  # Wiping all disks from clean state
  echo -e "\n\033[1mWiping all disks from clean state...\033[0m"
  set +e
  
  # Stop and remove any existing RAID arrays
  echo "Stopping existing RAID arrays..."
  for md in /dev/md*; do
    if [ -b "$md" ]; then
      mdadm --stop "$md" 2>/dev/null || true
    fi
  done
  
  # Wipe RAID superblocks from data drives
  echo "Wiping RAID superblocks from data drives..."
  for drive in "${DATA_DRIVES[@]}"; do
    if [ -b "$drive" ]; then
      echo "  Wiping $drive..."
      wipefs -a "$drive" 2>/dev/null || true
    fi
  done
  
  # Wipe partition tables from OS disk
  echo "Wiping partition table from OS disk..."
  if [ -b "$OS_DISK" ]; then
    wipefs -a "$OS_DISK" 2>/dev/null || true
  fi
  
  # Clear partition table signatures from all data drive partitions
  echo "Clearing partition signatures from data drives..."
  for drive in "${DATA_DRIVES[@]}"; do
    for part in "${drive}"?*; do
      if [ -b "$part" ]; then
        wipefs -a "$part" 2>/dev/null || true
      fi
    done
  done
  
  # Sync to ensure all writes are flushed
  sync
  
  set -e
  echo -e "\033[32mAll disks wiped clean.\033[0m"

  # Partitioning OS disk (NVMe)
  echo -e "\n\033[1mPartitioning OS disk (NVMe)...\033[0m"
  parted $OS_DISK -- mklabel gpt
  # Create partition 1: EFI boot partition ($OS_BOOT_PARTITION)
  parted $OS_DISK -- mkpart ESP fat32 1MiB 512MiB
  parted $OS_DISK -- set 1 boot on
  # Create partition 2: NixOS root partition ($OS_NIX_PARTITION)
  parted $OS_DISK -- mkpart Nix 512MiB 100%
  echo -e "\033[32mOS disk partitioned successfully.\033[0m"

  # Partitioning data drives for RAID
  echo -e "\n\033[1mPartitioning data drives for RAID...\033[0m"
  for drive in "${DATA_DRIVES[@]}"; do
    echo "Partitioning $drive..."
    parted $drive -- mklabel gpt
    parted $drive -- mkpart primary 1MiB 100%
    parted $drive -- set 1 raid on
  done
  echo -e "\033[32mData drives partitioned successfully.\033[0m"

  # Creating RAID array
  echo -e "\n\033[1mCreating RAID 5 array...\033[0m"
  # ${DATA_DRIVES[@]/%/1} appends "1" to each drive (sdb -> sdb1, etc.)
  mdadm --create $RAID_DEVICE --level=5 --raid-devices=4 "${DATA_DRIVES[@]/%/1}"
  echo -e "\033[32mRAID array created successfully.\033[0m"

  # Setting up encryption
  echo -e "\n\033[1mSetting up encryption...\033[0m"
  # OS encryption
  cryptsetup -q -v luksFormat $OS_NIX_PARTITION
  cryptsetup -q -v open $OS_NIX_PARTITION $OS_LUKS_DEVICE
  echo -e "\033[32mOS encryption setup completed.\033[0m"
  
  # Data encryption (RAID → LUKS)
  echo -e "\n\033[1mSetting up data encryption...\033[0m"
  cryptsetup -q -v luksFormat $RAID_DEVICE
  cryptsetup -q -v open $RAID_DEVICE $DATA_LUKS_DEVICE
  echo -e "\033[32mData encryption setup completed.\033[0m"

  # Setting up LVM for data
  echo -e "\n\033[1mSetting up LVM for data...\033[0m"
  pvcreate /dev/mapper/$DATA_LUKS_DEVICE
  vgcreate $VG_NAME /dev/mapper/$DATA_LUKS_DEVICE
  lvcreate -l 100%FREE -n $LV_NAME $VG_NAME
  echo -e "\033[32mLVM setup completed.\033[0m"

  # Creating filesystems
  echo -e "\n\033[1mCreating filesystems...\033[0m"
  # OS filesystems
  mkfs.fat -F32 -n boot $OS_BOOT_PARTITION
  mkfs.ext4 -F -L nix -m 0 /dev/mapper/$OS_LUKS_DEVICE
  
  # Data filesystem (RAID → LUKS → LVM → ext4)
  mkfs.ext4 -F -L data -m 0 /dev/mapper/$VG_NAME-$LV_NAME
  
  # Let mkfs catch its breath
  sleep 2
  echo -e "\033[32mFilesystems created successfully.\033[0m"

  # Mounting filesystems
  echo -e "\n\033[1mMounting filesystems...\033[0m"
  mount -t tmpfs none /mnt
  mkdir -pv /mnt/{boot,nix,data,etc/ssh,var/{lib,log}}
  mount /dev/disk/by-label/boot /mnt/boot
  mount /dev/disk/by-label/nix /mnt/nix
  mount /dev/disk/by-label/data /mnt/data
  mkdir -pv /mnt/nix/{secret/initrd,persist/{etc/ssh,var/{lib,log}}}
  chmod 0700 /mnt/nix/secret
  mount -o bind /mnt/nix/persist/var/log /mnt/var/log
  
  # Save mdadm configuration for reference (NixOS will auto-detect from superblocks)
  mkdir -p /mnt/etc/mdadm
  mdadm --detail --scan > /mnt/etc/mdadm/mdadm.conf
  echo -e "\033[32mFilesystems mounted successfully.\033[0m"

  # Generating initrd SSH host key
  echo -e "\n\033[1mGenerating initrd SSH host key...\033[0m"
  ssh-keygen -t ed25519 -N "" -C "" -f /mnt/nix/secret/initrd/ssh_host_ed25519_key
  echo -e "\033[32mSSH host key generated successfully.\033[0m"

  # Creating public age key for sops-nix
  echo -e "\n\033[1mConverting initrd public SSH host key into public age key for sops-nix...\033[0m"
  nix-shell --extra-experimental-features flakes -p ssh-to-age --run 'cat /mnt/nix/secret/initrd/ssh_host_ed25519_key.pub | ssh-to-age'
  echo -e "\033[32mAge public key generated successfully.\033[0m"

  # Completed
  echo -e "\n\033[1;32mAll steps completed successfully. NixOS is now ready to be installed.\033[0m\n"
  echo -e "Remember to commit and push the new server's public host key to sops-nix/update all sops encrypted files before installing!"
  echo -e "To install NixOS configuration for svr1shaikh, run the following command:\n"
  echo -e "\033[1msudo nixos-install --no-root-passwd --root /mnt --flake github:adyshake/shaikhlab#svr1shaikh\033[0m\n"
fi
