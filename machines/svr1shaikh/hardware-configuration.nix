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
      # `readlink /sys/class/net/enp6s0/device/driver` indicates "igb" is the ethernet driver for this device
      availableKernelModules = ["nvme" "xhci_pci" "ahci" "usb_storage" "sd_mod" "igb" "md_mod" "raid456"];
      luks = {
        reusePassphrases = true;
        devices = {
          "cryptroot" = {
            device = "/dev/nvme0n1p2";
            allowDiscards = true;
          };
          "data" = {
            device = "/dev/md/data";
            allowDiscards = true;
          };
        };
      };
    };
  };

  # Enable mdadm for RAID management
  # RAID 5 Configuration:
  # - Level: RAID 5 (striped with distributed parity)
  # - 4 drives: sda, sdb, sdc, sdd (4x 1.8TB WD Blue SA510 SSDs)
  # - Data striped across 3 drives, parity distributed across all drives
  # - Usable capacity: ~5.4TB (75% of 7.2TB total)
  # - Redundancy: Can survive failure of 1 drive
  # - Performance: Excellent read performance, good sequential write performance
  # - Rebuild time: Moderate (requires reading all remaining drives to rebuild)
  # The RAID array should be created manually first with:
  # mdadm --create /dev/md/data --level=5 --raid-devices=4 /dev/sda /dev/sdb /dev/sdc /dev/sdd --metadata=1.2 --name=data
  # Then save the config: mdadm --detail --scan >> /etc/mdadm.conf
  services.mdadm.enable = true;
  
  # Ensure mdadm is available in initrd for LUKS
  boot.initrd.services.swraid.enable = true;

  fileSystems = {
    "/" = {
      device = "none";
      fsType = "tmpfs";
      options = ["defaults" "size=4G" "mode=0755"];
    };
    "/boot" = {
      device = "/dev/disk/by-label/boot";
      fsType = "vfat";
      options = ["umask=0077"];
    };
    "/nix" = {
      device = "/dev/disk/by-label/nix";
      fsType = "ext4";
    };
    "/data" = {
      device = "/dev/disk/by-label/data";
      fsType = "ext4";
      options = ["defaults"];
    };
  };

  networking.useDHCP = lib.mkDefault true;
  networking.nameservers = [ "1.1.1.1" "9.9.9.9" ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
