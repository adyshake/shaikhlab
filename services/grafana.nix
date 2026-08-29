{
  config,
  pkgs,
  lib,
  vars,
  ...
}: {
  imports = [
    ./_acme.nix
    ./_nginx.nix
  ];

  sops.secrets = {
    "grafana-google-privatekey" = {
      format = "binary";
      sopsFile = ./../secrets/grafana-google-privatekey;
      owner = "grafana";
      group = "grafana";
      mode = "0440";
    };
    "grafana-google-sheets-client-email" = {
      owner = "grafana";
      group = "grafana";
    };
    "grafana-google-sheets-project-id" = {
      owner = "grafana";
      group = "grafana";
    };
    "fmp-api-key" = {
      format = "binary";
      sopsFile = ./../secrets/fmp-api-key;
      owner = "grafana";
      group = "grafana";
      mode = "0440";
      restartUnits = ["grafana.service"];
    };
    "grafana-secret-key" = {
      format = "binary";
      sopsFile = ./../secrets/grafana-secret-key;
      owner = "grafana";
      group = "grafana";
      mode = "0440";
      restartUnits = ["grafana.service"];
    };
  };

  services.grafana = {
    enable = true;

    provision = {
      enable = true;
      datasources.settings = {
        datasources = [
          {
            name = "Google Sheets";
            type = "grafana-googlesheets-datasource";
            uid = "googlesheets";
            jsonData = {
              authenticationType = "jwt";
              clientEmail = "$__file{${config.sops.secrets."grafana-google-sheets-client-email".path}}";
              defaultProject = "$__file{${config.sops.secrets."grafana-google-sheets-project-id".path}}";
              privateKeyPath = config.sops.secrets."grafana-google-privatekey".path;
              tokenUri = "https://oauth2.googleapis.com/token";
            };
          }
          {
            name = "Infinity";
            type = "yesoreyeram-infinity-datasource";
            uid = "infinity";
            access = "proxy";
          }
          {
            name = "DBnomics";
            type = "yesoreyeram-infinity-datasource";
            uid = "dbnomics";
            access = "proxy";
            jsonData = {
              allowedHosts = ["https://api.db.nomics.world"];
            };
          }
          {
            name = "FMP";
            type = "yesoreyeram-infinity-datasource";
            uid = "fmp";
            access = "proxy";
            jsonData = {
              auth_method = "apiKey";
              apiKeyKey = "apikey";
              apiKeyType = "query";
              allowedHosts = ["https://financialmodelingprep.com"];
              # Do not enable customHealthCheckUrl: Grafana would hit FMP
              # on Save & test / connection checks and burn the 300/min quota.
            };
            secureJsonData = {
              apiKeyValue = "$__file{${config.sops.secrets."fmp-api-key".path}}";
            };
          }
        ];
      };
      dashboards.settings.providers = [
        {
          name = "finance";
          type = "file";
          folder = "Finance";
          # File is source of truth. UI time-range/refresh edits were
          # otherwise kept in grafana.db and ignored later provision runs.
          allowUiUpdates = false;
          options.path = ./grafana/dashboards;
        }
      ];
    };

    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 3000;
        root_url = "https://grafana.adnanshaikh.com/";
        domain = "grafana.adnanshaikh.com";
      };
      security = {
        admin_user = "admin"; # TODO: change to sops secret
        admin_email = vars.userEmail;
        admin_password = "admin"; # TODO: change to sops secret
        cookie_secure = true;
        secret_key = "$__file{${config.sops.secrets."grafana-secret-key".path}}";
      };
      users = {
        allow_sign_up = false;
        # home_page = "";
        default_theme = "dark";
      };
      analytics.reporting_enabled = false;
    };

    # https://github.com/NixOS/nixpkgs/tree/master/pkgs/servers/monitoring/grafana/plugins
    declarativePlugins = with pkgs.grafanaPlugins; [
      grafana-googlesheets-datasource
      yesoreyeram-infinity-datasource
    ];
  };

  services.nginx = {
    virtualHosts = {
      "grafana.adnanshaikh.com" = {
        forceSSL = true;
        useACMEHost = "adnanshaikh.com";
        locations."/" = {
          recommendedProxySettings = true;
          proxyPass = "http://127.0.0.1:3000/";
        };
      };
    };
  };
}
