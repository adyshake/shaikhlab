{
  inputs,
  outputs,
  vars,
  ...
}: {
  imports = [
    inputs.home-manager.darwinModules.home-manager

    ./hardware-configuration.nix

    ./../../modules/macos/base.nix
  ];

  home-manager = {
    extraSpecialArgs = {inherit inputs outputs vars;};
    useGlobalPkgs = true;
    useUserPackages = true;
    users = {
      ${vars.userName} = {
        imports = [
          ./../../modules/home-manager/alacritty.nix
          ./../../modules/home-manager/base.nix
          ./../../modules/home-manager/firefox/default.nix
          ./../../modules/home-manager/fonts.nix
          ./../../modules/home-manager/git.nix
        ];
      };
    };
  };

  networking = {
    hostName = "mac1shaikh";
    computerName = "mac1shaikh";
    localHostName = "mac1shaikh";
  };
}

