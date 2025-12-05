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
      "alt-tab"
      "audacity"
      "betterdisplay"
      "caffeine"
      "discord"
      "docker-desktop"
      "exifcleaner"
      "firefox"
      "flycut"
      "grandperspective"
      "handbrake"
      "itsycal"
      "linearmouse"
      "rar"
      "spotify"
      "steam"
      "the-unarchiver"
      "visual-studio-code"
      "vlc"
      "whatsapp"
      "zed"
    ];
    masApps = {
      "Infuse" = 1136220934;
      "Tailscale" = 1475387142;
    };
  };
}
