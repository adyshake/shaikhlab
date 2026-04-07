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
        # Startup and region
        "browser.startup.homepage" = lib.mkDefault "about:blank";
        "browser.search.region" = "US";
        "browser.search.isUS" = true;
        "distribution.searchplugins.defaultLocale" = "en-US";
        "general.useragent.locale" = "en-US";

        # UI & Theme (Dark mode)
        "extensions.activeThemeID" = "firefox-compact-dark@mozilla.org";
        "layout.css.prefers-color-scheme.content-override" = 0;

        # Disable link preview on click and hold
        "browser.ml.linkPreview.enabled" = false;

        # Media
        "media.videocontrols.picture-in-picture.video-toggle.enabled" = false;

        # Allow dark mode on websites (LibreWolf's Resist Fingerprinting forces light mode by default)
        # We switch to Fingerprinting Protection (FPP) which is more granular, and exempt CSS prefers-color-scheme
        # "privacy.resistFingerprinting" = false;
        # "privacy.fingerprintingProtection" = true;
        # "privacy.fingerprintingProtection.overrides" = "+AllTargets,-CSSPrefersColorScheme";

        # History and auto-cleanup
        "places.history.expiration.max_pages" = 1000;
        "privacy.sanitize.sanitizeOnShutdown" = true;

        # Disable default browser check
        "browser.shell.checkDefaultBrowser" = false;

        # Downloads location
        "browser.download.useDownloadDir" = true;
        "browser.download.folderList" = 2;
        "browser.download.dir" = "/Users/${vars.userName}/Downloads";
        "browser.download.lastDir" = "/Users/${vars.userName}/Downloads";

        # Password manager and autofill off (using Bitwarden instead)
        "signon.rememberSignons" = false;
        "signon.autofillForms" = false;
        "extensions.formautofill.addresses.enabled" = false;
        "extensions.formautofill.creditCards.enabled" = false;

        # Enable userChrome and UI customization
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

        # Custom toolbar settings
        "browser.uiCustomization.state" = builtins.toJSON {
          currentVersion = 23;
          newElementCount = 10;
          placements = {
            widget-overflow-fixed-list = [];
            # Nav bar: stock controls, then URL bar, then pinned extensions (order matters).
            nav-bar = [
              "back-button"
              "forward-button"
              "stop-reload-button"
              "home-button"
              "urlbar-container"
              "downloads-button"
              "unified-extensions-button"
              # Pinned extensions — keep in sync with ExtensionSettings default_area = "navbar" in policies.nix
              "_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action" # Bitwarden
              "toggle-native-tab_bar_irvinm_addons_mozilla_org-browser-action" # Toggle Native Tab Bar
              "jid0-3GUEt1r69sQNSrca5p8kx9Ezc3U_jetpack-browser-action" # Terms of Service; Didn't Read
              
            ];
            toolbar-menubar = ["menubar-items"];
            TabsToolbar = ["tabbrowser-tabs"];
            PersonalToolbar = ["personal-bookmarks"];
          };
          seen = [
            "save-to-pocket-button"
            "developer-button"
            "ublock0_raymondhill_net-browser-action"
            "sponsorblocker_ajay_app-browser-action"
            "addon_darkreader_org-browser-action"
            "privacypass_kagi_com-browser-action"
            "gdpr_cavi_au_dk-browser-action"
            "redirector_einaregilsson_com-browser-action"
            "d7742d87-e61d-4b78-b8a1-b469842139fa_-browser-action"
            "deArrow_ajay_app-browser-action"
            "2662ff67-b302-4363-95f3-b050218bd72c_-browser-action"
            "7a7a4a92-a2a0-41d1-9fd7-1e92480d612d_-browser-action"
            "amptra_keepa_com-browser-action"
            "7esoorv3_alefvanoon_anonaddy_me-browser-action"
            "toggle-native-tab_bar_irvinm_addons_mozilla_org-browser-action"
          ];
          dirtyAreaCache = [
            "nav-bar"
            "toolbar-menubar"
            "TabsToolbar"
            "PersonalToolbar"
            "widget-overflow-fixed-list"
          ];
        };
      };
      userChrome = ''
        /* For Toggle Native Tab Bar extension */
        #main-window[titlepreface*=" "] #TabsToolbar {
            display: none;
        }
      '';
      extensions.force = true;
      extensions.settings = {
        # Untrap for YouTube settings
        # Stylus
        "{7a7a4a92-a2a0-41d1-9fd7-1e92480d612d}" = {
          force = true;
          settings = {
            dbInChromeStorage = true;
          };
        };
        "{2662ff67-b302-4363-95f3-b050218bd72c}" = {
          force = true;
          settings = {
            # Core untrap settings
            "untrap_global_enable" = true;
            "untrap_global_hide_all_ads" = true;

            # Hide Home Page (suggestions/feed)
            "untrap_home_hide_suggestions" = true;

            # Hide Sidebar
            "untrap_sidebar_hide_entire_sidebar" = true;

            # Video page - hide related videos and center content
            "untrap_video_page_hide_related_videos" = true;
            "untrap_video_page_center_content" = true;
            "untrap_video_player_hide_end_screen_suggestions" = true;

            # Search page and suggestions
            "untrap_search_bar_hide_suggestions" = true;
            "untrap_search_hide_results_people_also_search" = true;
            "untrap_search_hide_results_for_you" = true;
          };
        };
      };
    };
  };
}
