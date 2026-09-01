{
  inputs,
  outputs,
  vars,
  ...
}: {
  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.impermanence.nixosModules.impermanence
    inputs.nixarr.nixosModules.default

    ./hardware-configuration.nix

    ./../../modules/nixos/auto-update.nix
    ./../../modules/nixos/base.nix
    ./../../modules/nixos/remote-unlock.nix

    ./../../services/drive-health.nix # Requires: mxroute-smtp-password (imports ./mail.nix)
    ./../../services/nixarr.nix # Requires: wg.conf, transmission-rpc-credentials
    ./../../services/ntfy.nix # Requires: ntfy-secret
    ./../../services/tailscale.nix # Requires: tailscale-authkey
    ./../../services/homeassistant.nix
    ./../../services/zwave-js-ui.nix
    ./../../services/blocky.nix
    ./../../services/grafana.nix # Requires: grafana-admin-password
    ./../../services/forgejo.nix # Requires: forgejo-admin-password
    ./../../services/sui.nix
    ./../../services/wastebin.nix
    ./../../services/immich.nix
  ];

  home-manager = {
    extraSpecialArgs = {inherit inputs outputs vars;};
    useGlobalPkgs = true;
    useUserPackages = true;
    users = {
      ${vars.userName} = {
        imports = [
          ./../../modules/home-manager/base.nix
          ./../../modules/home-manager/git.nix
        ];
      };
    };
  };

  networking.hostName = "svr1shaikh";
}
