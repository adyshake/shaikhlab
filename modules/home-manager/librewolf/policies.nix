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
      {
        Name = "@maps";
        Description = "Google Maps search";
        URLTemplate = "https://www.google.com/maps/search/{searchTerms}";
        Method = "GET";
        IconURL = "https://www.google.com/images/branding/product/ico/maps15_bnuw3a_32dp.ico";
        Alias = "@maps";
      }
      {
        Name = "@yt";
        Description = "YouTube search";
        URLTemplate = "https://www.youtube.com/results?search_query={searchTerms}";
        Method = "GET";
        IconURL = "https://www.youtube.com/favicon.ico";
        Alias = "@yt";
      }
    ];
  };

  # Extensions — force-installed via Mozilla policy templates
  # Docs: https://mozilla.github.io/policy-templates/#extensionsettings
  #
  # To add a new extension:
  #   1. Get the extension ID (use this exact string as the attribute name below):
  #      nix run github:tupakkatapa/mozid -- 'https://addons.mozilla.org/en/firefox/addon/<slug>'
  #   2. Add an entry using this template:
  #      "<extension-id-from-mozid>" = {
  #        install_url = "https://addons.mozilla.org/firefox/downloads/latest/<slug>/latest.xpi";
  #        installation_mode = "force_installed";
  #        default_area = "menupanel";  # or "navbar" to pin to toolbar
  #      };
  #   Toolbar order in browser.uiCustomization.state: Firefox derives widget IDs as
  #   lowercase(extensionId) with @ and . replaced by _, then suffixed with -browser-action.
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
    # Toggle Native Tab Bar (mozid: toggle-native-tab-bar)
    "Toggle-Native-Tab_Bar@irvinm.addons.mozilla.org" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/toggle-native-tab-bar/latest.xpi";
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
    "{7a7a4a92-a2a0-41d1-9fd7-1e92480d612d}" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/styl-us/latest.xpi";
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

  # Bookmarks — populate URL bar autocomplete
  Bookmarks = [
    {
      Title = "Gmail";
      URL = "https://gmail.com";
      Placement = "toolbar";
      Folder = "Quick Access";
    }
    {
      Title = "Google Calendar";
      URL = "https://calendar.google.com";
      Placement = "toolbar";
      Folder = "Quick Access";
    }
    {
      Title = "Google Drive";
      URL = "https://drive.google.com";
      Placement = "toolbar";
      Folder = "Quick Access";
    }
    {
      Title = "Gemini";
      URL = "https://gemini.google.com";
      Placement = "toolbar";
      Folder = "Quick Access";
    }
    {
      Title = "Radarr";
      URL = "https://radarr.adnanshaikh.com";
      Placement = "toolbar";
      Folder = "Homelab";
    }
    {
      Title = "Sonarr";
      URL = "https://sonarr.adnanshaikh.com";
      Placement = "toolbar";
      Folder = "Homelab";
    }
    {
      Title = "Transmission";
      URL = "https://transmission.adnanshaikh.com";
      Placement = "toolbar";
      Folder = "Homelab";
    }
    {
      Title = "Home Assistant";
      URL = "https://ha.adnanshaikh.com";
      Placement = "toolbar";
      Folder = "Homelab";
    }
  ];

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
      "https://git.adnanshaikh.com"
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
