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

  services.grafana = {
    enable = true;

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
