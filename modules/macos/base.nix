{
  pkgs,
  vars,
  ...
}: {
  imports = [
    ./_dock.nix
    ./_packages.nix
  ];

  nixpkgs.config.allowUnfree = true;
  nix = {
    package = pkgs.nix;
    gc = {
      automatic = true;
      interval = {
        Weekday = 0;
        Hour = 0;
        Minute = 0;
      };
      options = "--delete-older-than 7d";
    };
    optimise = {
      automatic = true;
    };
    settings = {
      experimental-features = "nix-command flakes";
      trusted-users = [
        "root"
        "@admin"
      ];
    };
  };

  # inspo: https://github.com/nix-darwin/nix-darwin/issues/1339
  ids.gids.nixbld = 350;

  programs.zsh.enable = true;
  security.pam.services.sudo_local.touchIdAuth = true;

  services = {
    tailscale.enable = true;
  };

  users.users.${vars.userName}.home = "/Users/${vars.userName}";

  system = {
    primaryUser = vars.userName;
    startup.chime = false;
    defaults = {
      loginwindow.LoginwindowText = "If lost, contact ${vars.userEmail}";
      screencapture.location = "~/Users/${vars.userName}/Documents/Screenshots";

      dock = {
        autohide = true;
        mru-spaces = false;
        tilesize = 48;
        # Disable all hot corners (1 = noop)
        wvous-tl-corner = 1;
        wvous-tr-corner = 1;
        wvous-bl-corner = 1;
        wvous-br-corner = 1;
      };

      finder = {
        AppleShowAllExtensions = true;
        FXPreferredViewStyle = "clmv";
      };

      menuExtraClock = {
        ShowSeconds = false;
        Show24Hour = false;
        ShowAMPM = true;
      };

      NSGlobalDomain = {
        AppleICUForce24HourTime = false;
        AppleInterfaceStyle = "Dark";
        # inspo: https://apple.stackexchange.com/questions/261163/default-value-for-nsglobaldomain-initialkeyrepeat
        KeyRepeat = 2;
        InitialKeyRepeat = 15;
      };

      CustomUserPreferences = {
        # Disable Siri
        "com.apple.Siri" = {
          "UAProfileCheckingStatus" = 0;
          "siriEnabled" = 0;
        };
        # Disable personalized ads
        "com.apple.AdLib" = {
          allowApplePersonalizedAdvertising = false;
        };
      };
    };
  };

  local = {
    dock = {
      enable = true;
      username = vars.userName;
      entries = [
        {path = "/Applications/Firefox.app";}
        {path = "/Applications/Discord.app";}
        {path = "/Applications/Zed.app";}
        {path = "/Applications/Alacritty.app";}
        {path = "/Applications/Sublime Text.app";}
        {
          path = "/Users/${vars.userName}/Downloads";
          section = "others";
          options = "--sort dateadded --view fan --display stack";
        }
      ];
    };
  };

  system.activationScripts.Wallpaper.text = ''
    echo >&2 "Setting up wallpaper..."
    osascript -e 'tell application "Finder" to set desktop picture to POSIX file "/System/Library/Desktop Pictures/Solid Colors/Black.png"'
  '';

  system.stateVersion = 4;
}
