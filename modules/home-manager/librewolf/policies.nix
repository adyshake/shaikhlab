{
  # LibreWolf defaults — kept here for deterministic builds
  AppUpdateURL = "https://localhost";
  DisableAppUpdate = true;
  OverrideFirstRunPage = "";
  OverridePostUpdatePage = "";
  DisableSystemAddonUpdate = true;
  DisableProfileImport = false;
  DisableFirefoxStudies = true;
  DisableTelemetry = true;
  DisableFeedbackCommands = true;
  DisablePocket = true;
  DisableSetDesktopBackground = false;
  DisableDeveloperTools = false;
  NoDefaultBookmarks = true;
  SkipTermsOfUse = true;
  WebsiteFilter = {
    Block = ["https://localhost/*"];
    Exceptions = ["https://localhost/*"];
  };
  SupportMenu = {
    Title = "LibreWolf Issue Tracker";
    URL = "https://codeberg.org/librewolf/issues";
  };

  # Custom search engines
  SearchEngines = {
    PreventInstalls = false;
    Remove = [
      "Google"
      "Bing"
      "Amazon.com"
      "eBay"
      "Twitter"
      "DuckDuckGo"
      "Wikipedia (en)"
      "LibRedirect"
      "Perplexity"
    ];
    Default = "Kagi";
    Add = [
      {
        Name = "Kagi";
        Description = "A privacy-focused, user-centric search engine.";
        URLTemplate = "https://kagi.com/search?q={searchTerms}";
        Method = "GET";
        IconURL = "https://kagi.com/favicon-32x32.png";
        SuggestURLTemplate = "https://kagisuggest.com/api/autosuggest?q={searchTerms}";
      }
    ];
  };

  # Extensions — force-installed via Mozilla policy templates
  # Docs: https://mozilla.github.io/policy-templates/#extensionsettings
  #
  # To add a new extension:
  #   1. Get the extension ID:
  #      nix run github:tupakkatapa/mozid -- 'https://addons.mozilla.org/en/firefox/addon/<slug>'
  #   2. Add an entry below using this template:
  #      "<extension-id>" = {
  #        install_url = "https://addons.mozilla.org/firefox/downloads/latest/<slug>/latest.xpi";
  #        installation_mode = "force_installed";
  #        default_area = "menupanel";  # or "navbar" to pin to toolbar
  #      };
  ExtensionSettings = {
    "*" = {
      installation_mode = "blocked";
    };
    # uBlock Origin
    "uBlock0@raymondhill.net" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
      installation_mode = "force_installed";
      default_area = "menupanel";
    };
    # Vimium
    "{d7742d87-e61d-4b78-b8a1-b469842139fa}" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/vimium-ff/latest.xpi";
      installation_mode = "force_installed";
      default_area = "menupanel";
    };
    # DeArrow
    "deArrow@ajay.app" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/dearrow/latest.xpi";
      installation_mode = "force_installed";
      default_area = "menupanel";
    };
    # Untrap for YouTube
    "{2662ff67-b302-4363-95f3-b050218bd72c}" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/untrap-for-youtube/latest.xpi";
      installation_mode = "force_installed";
      default_area = "menupanel";
    };
    # SponsorBlock
    "sponsorBlocker@ajay.app" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/sponsorblock/latest.xpi";
      installation_mode = "force_installed";
      default_area = "menupanel";
    };
    # Bitwarden
    "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
      installation_mode = "force_installed";
      default_area = "navbar";
    };
    # Dark Reader
    "addon@darkreader.org" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/darkreader/latest.xpi";
      installation_mode = "force_installed";
      default_area = "menupanel";
    };
    # Stylus
    "{c102b0e7-893d-444f-917c-fc530de507c9}" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/styl-us/latest.xpi";
      installation_mode = "force_installed";
      default_area = "menupanel";
    };
    # Kagi Search
    "search@kagi.com" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/kagi-search-for-firefox/latest.xpi";
      installation_mode = "force_installed";
      default_area = "menupanel";
    };
    # Kagi Privacy Pass
    "privacypass@kagi.com" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/kagi-privacy-pass/latest.xpi";
      installation_mode = "force_installed";
      default_area = "menupanel";
    };
    # Consent-O-Matic
    "gdpr@cavi.au.dk" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/consent-o-matic/latest.xpi";
      installation_mode = "force_installed";
      default_area = "menupanel";
    };
    # Terms of Service; Didn't Read
    "jid0-3GUEt1r69sQNSrca5p8kx9Ezc3U@jetpack" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/terms-of-service-didnt-read/latest.xpi";
      installation_mode = "force_installed";
      default_area = "navbar";
    };
    # LibRedirect
    "7esoorv3@alefvanoon.anonaddy.me" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/libredirect/latest.xpi";
      installation_mode = "force_installed";
      default_area = "menupanel";
    };
  };

  # Clear data on shutdown
  SanitizeOnShutdown = {
    Cache = true;
    Cookies = true;
    History = true;
    Sessions = true;
    FormData = true;
    Downloads = true;
    Locked = true;
  };

  # Cookie exceptions — these sites keep cookies through shutdown
  Cookies = {
    Allow = [
      "https://accounts.google.com"
      "https://mail.google.com"
      "https://calendar.google.com"
      "https://drive.google.com"
      "https://docs.google.com"
      "https://meet.google.com"
      "https://www.google.com"
      "https://gemini.google.com"
      "https://youtube.com"
      "https://github.com"
      "https://amazon.com"
      "https://kagi.com"
      "https://bitwarden.com"
    ];
    Behavior = "reject-tracker-and-partition-foreign";
    Locked = true;
  };

  # LibreWolf default — uninstall bundled search engine add-ons
  Extensions = {
    Uninstall = [
      "google@search.mozilla.org"
      "bing@search.mozilla.org"
      "amazondotcom@search.mozilla.org"
      "ebay@search.mozilla.org"
      "twitter@search.mozilla.org"
    ];
  };
}
