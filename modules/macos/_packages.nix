{
  config,
  inputs,
  vars,
  ...
}: {
  imports = [
    inputs.nix-homebrew.darwinModules.nix-homebrew
  ];

  nix-homebrew = {
    enable = true;
    enableRosetta = true;
    user = vars.userName;
    mutableTaps = false;
    taps = {
      "homebrew/homebrew-bundle" = inputs.homebrew-bundle;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
      "homebrew/homebrew-core" = inputs.homebrew-core;
    };
  };

  homebrew = {
    enable = true;
    global = {
      autoUpdate = true;
    };
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "zap";
    };
    brews = [
      "trash"
    ];
    taps = builtins.attrNames config.nix-homebrew.taps;
    casks = [
      "alacritty"
      "caffeine"
      "discord"
      "exifcleaner"
      "firefox"
      "grandperspective"
      "handbrake"
      "linearmouse"
      "obsidian"
      "rar"
      "raycast"
      "spotify"
      "steam"
      "the-unarchiver"
      "visual-studio-code"
      "vlc"
      "whatsapp"
      "zed"
    ];
    masApps = {
      "Tailscale" = 1475387142;
    };
  };
}
