{
  pkgs,
  vars,
  ...
}: let
  urlbarSelectJs = ../home-manager/librewolf/urlbar-select.js;
  autoconfigSandboxPref = pkgs.writeText "shaikhlab-autoconfig.js" ''
    pref("general.config.sandbox_enabled", false);
  '';
  urlbarSelectStub = pkgs.writeText "shaikhlab-urlbar-stub.js" ''
    // SHAIKHLAB_URLBAR_SELECT_BEGIN
    try {
      const loader = Components.classes["@mozilla.org/moz/jssubscript-loader;1"].getService(
        Components.interfaces.mozIJSSubScriptLoader
      );
      loader.loadSubScript(
        "file:///Applications/LibreWolf.app/Contents/Resources/shaikhlab-urlbar-select.js"
      );
    } catch (e) {
      try {
        const {Services} = ChromeUtils.importESModule(
          "resource://gre/modules/Services.sys.mjs"
        );
        Services.scriptloader.loadSubScript(
          "file:///Applications/LibreWolf.app/Contents/Resources/shaikhlab-urlbar-select.js"
        );
      } catch (e2) {}
    }
    // SHAIKHLAB_URLBAR_SELECT_END
  '';
  patchLibrewolfCfg = pkgs.writeText "patch-librewolf-cfg.py" ''
    from pathlib import Path
    import sys

    cfg = Path(sys.argv[1])
    stub = Path(sys.argv[2]).read_text()
    begin = "// SHAIKHLAB_URLBAR_SELECT_BEGIN"
    end = "// SHAIKHLAB_URLBAR_SELECT_END"
    if not cfg.is_file():
        raise SystemExit(0)
    text = cfg.read_text()
    if begin in text:
        pre, rest = text.split(begin, 1)
        _, post = rest.split(end, 1)
        text = pre.rstrip() + "\n" + stub
        if post.strip():
            text += post if post.startswith("\n") else "\n" + post
    else:
        if not text.endswith("\n"):
            text += "\n"
        text += stub
    if not text.endswith("\n"):
        text += "\n"
    cfg.write_text(text)
  '';
in {
  imports = [
    ./_dock.nix
    ./_icons.nix
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
        {path = "/Applications/LibreWolf.app";}
        {path = "/Applications/Discord.app";}
        {path = "/Applications/Yomu.app";}
        {path = "/Applications/Cursor.app";}
        {path = "/Applications/iTerm.app";}
        {path = "/Applications/Sublime Text.app";}
        {path = "/System/Applications/Reminders.app";}
        {
          path = "/Users/${vars.userName}/Downloads";
          section = "others";
          options = "--sort dateadded --view fan --display stack";
        }
      ];
    };
  };

  system.activationScripts.postActivation.text = let
    policies = builtins.toJSON {
      policies = import ./../home-manager/librewolf/policies.nix;
    };
  in ''
    echo >&2 "Removing quarantine attribute from LibreWolf..."
    xattr -r -d com.apple.quarantine /Applications/LibreWolf.app 2>/dev/null || true

    echo >&2 "Writing LibreWolf policies..."
    resources="/Applications/LibreWolf.app/Contents/Resources"
    if [ -d "/Applications/LibreWolf.app" ]; then
      mkdir -p "$resources/distribution" "$resources/defaults/pref"
      echo '${policies}' > "$resources/distribution/policies.json"

      echo >&2 "Installing LibreWolf start-page URL-bar select..."
      cp ${autoconfigSandboxPref} "$resources/defaults/pref/shaikhlab.js"
      cp ${urlbarSelectJs} "$resources/shaikhlab-urlbar-select.js"
      ${pkgs.python3}/bin/python3 ${patchLibrewolfCfg} "$resources/librewolf.cfg" ${urlbarSelectStub}
    fi
  '';

  system.activationScripts.Wallpaper.text = ''
    echo >&2 "Setting up wallpaper..."
    osascript -e 'tell application "Finder" to set desktop picture to POSIX file "/System/Library/Desktop Pictures/Solid Colors/Black.png"'
  '';

  system.stateVersion = 4;
}
