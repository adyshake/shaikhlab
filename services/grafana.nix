{
  config,
  pkgs,
  lib,
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
        cookie_secure = true;
      };
      analytics.reporting_enabled = false;
    };
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
