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
    
    # Configure Grafana to work behind nginx reverse proxy
    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 3000;
        root_url = "https://grafana.adnanshaikh.com/";
        domain = "grafana.adnanshaikh.com";
        # Don't enforce domain checking - let nginx handle it
        enforce_domain = false;
        # Serve from root path
        serve_from_sub_path = false;
      };
      
      # Security settings
      security = {
        admin_user = "admin";
        # Admin password should be set via SOPS secret or changed on first login
        cookie_secure = true;
        cookie_samesite = "lax";
      };
      
      # Database (SQLite by default, can be changed to PostgreSQL)
      database = {
        type = "sqlite3";
        path = "/var/lib/grafana/grafana.db";
      };
      
      # Logging
      log = {
        mode = "console file";
        level = "info";
      };
      
      # Analytics
      analytics = {
        reporting_enabled = false;
      };
    };
  };

  # Allow access to Grafana web interface (default port 3000)
  # Note: Only needed if accessing directly, but we're using nginx reverse proxy
  # networking.firewall.allowedTCPPorts = [3000];

  services.nginx = {
    virtualHosts = {
      "grafana.adnanshaikh.com" = {
        forceSSL = true;
        useACMEHost = "adnanshaikh.com";
        locations."/" = {
          recommendedProxySettings = true;
          proxyPass = "http://127.0.0.1:3000/";
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Server $host;
            proxy_redirect off;
          '';
        };
      };
    };
  };

}
