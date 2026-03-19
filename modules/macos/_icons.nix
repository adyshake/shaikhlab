{inputs, ...}: {
  imports = [
    inputs.nix-darwin-custom-icons.darwinModules.default
  ];

  environment.customIcons = {
    enable = true;
    clearCacheOnActivation = true;
    icons = [
      {
        path = "/Applications/Alacritty.app";
        icon = ./../../icons/alacritty.icns;
      }
    ];
  };
}
