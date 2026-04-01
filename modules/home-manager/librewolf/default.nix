{
  lib,
  pkgs,
  inputs,
  vars,
  ...
}: {
  programs.librewolf = {
    enable = true;
    # On macOS, LibreWolf is installed via Homebrew Cask
    package = lib.mkIf pkgs.stdenv.isDarwin null;
    # On macOS, policies are applied via activation script in modules/macos/base.nix
    # since the Homebrew-managed app bundle can't be written to by Home Manager.
    policies = lib.mkIf pkgs.stdenv.isLinux (import ./policies.nix);
    profiles.${vars.userName} = {
      name = vars.userName;
      isDefault = true;
      settings = {
        "browser.startup.homepage" = lib.mkDefault "about:blank";
        "browser.search.region" = "US";
        "browser.search.isUS" = true;
        "distribution.searchplugins.defaultLocale" = "en-US";
        "general.useragent.locale" = "en-US";
        "places.history.expiration.max_pages" = 1000;
        "privacy.sanitize.sanitizeOnShutdown" = true;
      };
      userChrome = ''
        /* For Toggle Native Tab Bar extension */
        #main-window[titlepreface*=" "] #TabsToolbar {
            display: none;
        }
      '';
    };
  };
}
