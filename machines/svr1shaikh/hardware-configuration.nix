{
  config,
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot = {
    initrd = {
      # Kernel modules required for the storage stack:
      # - nvme: NVMe SSD support for OS drive
      # - xhci_pci, ahci: USB and SATA controllers
      # - usb_storage, sd_mod: USB and SCSI disk support
      # - raid456, md_mod: Software RAID support for data drives
      # - dm_mod, dm_crypt: Device mapper and LUKS encryption
      availableKernelModules = ["nvme" "xhci_pci" "ahci" "usb_storage" "sd_mod" "raid456" "md_mod" "dm_mod" "dm_crypt"];
            
      luks = {
        # Reuse passphrases to avoid multiple password prompts during boot
        reusePassphrases = true;
        devices = {
          # OS drive encryption (NVMe)
          "cryptroot" = {
            device = "/dev/nvme0n1p2";  # OS partition on NVMe
            allowDiscards = true;        # Enable TRIM for SSD performance
          };
          # Data drive encryption (RAID array)
          "cryptdata" = {
            device = "/dev/md0";        # RAID5 array from 4x 2.5TB SSDs
            allowDiscards = true;        # Enable TRIM for SSD performance
          };
        };
      };
    };
  };

  # Filesystem support - only ext4 needed for this setup
  boot.supportedFilesystems = ["ext4"];

  fileSystems = {
    # Root filesystem - temporary in-memory filesystem
    # This enables impermanence: all changes are lost on reboot
    "/" = {
      device = "none";
      fsType = "tmpfs";
      options = ["defaults" "size=4G" "mode=0755"];
    };
    
    # EFI boot partition on NVMe
    "/boot" = {
      device = "/dev/disk/by-label/boot";
      fsType = "vfat";
      options = ["umask=0077"];  # Restrict boot partition access
    };
    
    # NixOS root filesystem (encrypted, with impermanence)
    "/nix" = {
      device = "/dev/disk/by-label/nix";
      fsType = "ext4";
    };
    
    # Data storage filesystem (RAID5 → LUKS → LVM → ext4)
    "/data" = {
      device = "/dev/mapper/storage-data";  # LVM logical volume
      fsType = "ext4";
    };
  };

  # Enable software RAID support in initrd
  # Required for assembling the RAID5 array during boot
  boot.swraid = {
    enable = true;
    
    # Replace with the output from step 9.
    mdadmConf = ''
      // NOTE: Dump the output from `mdadm --detail --scan --verbose` here.
      ARRAY /dev/md0 level=raid5 num-devices=4 metadata=1.2 spares=1 UUID=45043155:dd96c83a:ee776fee:f003b4f3
   devices=/dev/sda1,/dev/sdb1,/dev/sdd1,/dev/sde1
      MAILADDR shaikhlab@adnanshaikh.com
    '';
  };
  
  # Enable LVM support in initrd
  # Required for activating the storage volume group during boot
  boot.initrd.services.lvm.enable = true;

  # Network configuration
  networking.useDHCP = lib.mkDefault true;
  
  # Platform and CPU configuration
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
