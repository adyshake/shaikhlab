{
  lib,
  pkgs,
  ...
}: let
  # Stable GUID so the same profile is reused across rebuilds and can be
  # referenced as the default bookmark below.
  profileGuid = "shaikhlab-iterm2-default";
in {
  # iTerm2 reads any JSON in DynamicProfiles/ at launch. Managing the profile
  # this way keeps it declarative without fighting iTerm2's main plist, which it
  # rewrites on quit.
  home.file."Library/Application Support/iTerm2/DynamicProfiles/shaikhlab.json" = lib.mkIf pkgs.stdenv.isDarwin {
    text = builtins.toJSON {
      Profiles = [
        {
          Name = "shaikhlab";
          Guid = profileGuid;
          # "Recycle" == "Reuse previous session's directory", so a Cmd+D split
          # inherits the current pane's working directory.
          "Custom Directory" = "Recycle";
          # Monaco for all text. iTerm2 renders icon glyphs (lsd/omz) with the
          # separate non-ASCII font below, so Monaco stays the text font.
          "Normal Font" = "Monaco 18";
          "Use Non-ASCII Font" = true;
          # PostScript name of Symbols Nerd Font Mono (installed via fonts.nix).
          "Non Ascii Font" = "SymbolsNFM 18";
        }
      ];
    };
  };

  # Point iTerm2 at the dynamic profile as its default so new windows/tabs/splits
  # all use the Recycle behaviour above.
  targets.darwin.defaults = lib.mkIf pkgs.stdenv.isDarwin {
    "com.googlecode.iterm2" = {
      "Default Bookmark Guid" = profileGuid;
    };
  };
}
