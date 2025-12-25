{
  lib,
  pkgs,
  inputs,
  vars,
  ...
}: {
  programs.firefox = {
    enable = true;
    # On macOS, Firefox is installed via Homebrew Cask, so don't install the package
    # but still configure it (extensions, settings, profiles, themes)
    # On Linux, install and configure Firefox via Home Manager
    package = lib.mkIf pkgs.stdenv.isDarwin null;
    profiles.${vars.userName} = {
      name = vars.userName;
      isDefault = true;
      settings = {
        "browser.startup.homepage" = lib.mkDefault "about:home";
        "browser.search.region" = "US";
        "browser.search.isUS" = true;
        "distribution.searchplugins.defaultLocale" = "en-US";
        "general.useragent.locale" = "en-US";
      };
      search.engines = {
        "Nix Packages" = {
          urls = [
            {
              template = "https://search.nixos.org/packages";
              params = [
                {
                  name = "type";
                  value = "packages";
                }
                {
                  name = "query";
                  value = "{searchTerms}";
                }
              ];
            }
          ];
          icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
          definedAliases = ["@np"];
          search.force = true;
        };
      };
      extensions.packages = with inputs.firefox-addons.packages.${pkgs.system}; [
        dearrow
        # untrap-for-youtube # has unfree license
        sponsorblock
        bitwarden
        darkreader
        ublock-origin
        vimium
        stylus
        redirector
        # keepa # has unfree license
        kagi-search
        kagi-privacy-pass
        consent-o-matic
      ];
    };
  };

}

