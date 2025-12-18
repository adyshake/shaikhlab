{
  config,
  lib,
  modulesPath,
  vars,
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
            device = "/dev/md0";
            allowDiscards = true;
          };
        };
      };
    };
    # Ensure mdadm is available in initrd for LUKS
    swraid.enable = true;
  };

  # Configure mdadm to auto-assemble the RAID array
  # Generated with: mdadm --detail --scan
  environment.etc."mdadm.conf".text = ''
    ARRAY /dev/md0 metadata=1.2 UUID=e229efd8:ba77234e:59375065:9edda13b
    MAILADDR ${vars.userEmail}
  '';

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
  # Use Blocky as DNS resolver (Blocky will forward to upstream resolvers)
  networking.nameservers = [ "127.0.0.1" ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
