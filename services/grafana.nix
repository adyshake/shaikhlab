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
    "grafana-google-sheets-client-email" = {owner = "grafana"; group = "grafana";};
    "grafana-google-sheets-project-id" = {owner = "grafana"; group = "grafana";};
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
        ];
      };
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
