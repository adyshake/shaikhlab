{
  inputs,
  outputs,
  vars,
  ...
}: {
  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.impermanence.nixosModules.impermanence

    ./hardware-configuration.nix

    ./../../modules/nixos/auto-update.nix
    ./../../modules/nixos/base.nix
    ./../../modules/nixos/remote-unlock.nix

    ./../../services/nextcloud.nix
    ./../../services/tailscale.nix
  ];

  home-manager = {
    extraSpecialArgs = {inherit inputs outputs vars;};
    useGlobalPkgs = true;
    useUserPackages = true;
    users = {
      ${vars.userName} = {
        imports = [
          ./../../modules/home-manager/base.nix
        ];
      };
    };
  };

  networking.hostName = "svr1shaikh";

  # Configure mdadm monitoring to prevent service crash
  # mdadm requires either MAILADDR or PROGRAM to be set, otherwise mdmon will crash
  services.mdadm.monitor = {
    enable = true;
    mailTo = "shaikhlab@adnanshaikh.com";  # Email for RAID alerts
    runOnDegraded = true;
  };
}
