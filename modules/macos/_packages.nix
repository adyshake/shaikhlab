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
    autoMigrate = true;
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
      "trash-cli"
      "imagemagick"
      "ghostscript"
      "jrnl"
      "zbar"
    ];
    taps = builtins.attrNames config.nix-homebrew.taps;
    casks = [
      "alacritty"
      "alt-tab"
      "audacity"
      "betterdisplay"
      "caffeine"
      "cursor"
      "discord"
      "docker-desktop"
      "exifcleaner"
      "librewolf"
      "flycut"
      "grandperspective"
      "hammerspoon"
      "handbrake-app"
      "itsycal"
      "linearmouse"
      "meetingbar"
      "rar"
      "spotify"
      "steam"
      "the-unarchiver"
      "visual-studio-code"
      "vlc"
      "whatsapp"
      "zed"
    ];
    # TODO: masApps hangs on `darwin-rebuild switch` (see TODO.md). Re-enable
    # once the root cause is fixed.
    # masApps = {
    #   "Infuse" = 1136220934;
    #   "Tailscale" = 1475387142;
    #   "Yomu EBook Reader" = 562211012;
    # };
  };
}
