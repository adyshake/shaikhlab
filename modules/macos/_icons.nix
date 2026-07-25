{inputs, ...}: {
  imports = [
    inputs.nix-darwin-custom-icons.darwinModules.default
  ];

  # No custom app icons currently. iTerm2 ships its own icon; drop a .icns into
  # ../../icons and add an entry here if you want to override it.
  environment.customIcons = {
    enable = false;
    clearCacheOnActivation = true;
    icons = [];
  };
}
