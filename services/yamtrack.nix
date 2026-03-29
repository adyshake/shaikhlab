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

  sops.secrets."yamtrack-env" = {
    format = "binary";
    sopsFile = ./../secrets/yamtrack-env;
  };

  virtualisation.podman = {
    enable = true;
    autoPrune.enable = true;
    dockerCompat = true;
    defaultNetwork.settings = {
      dns_enabled = true;
    };
  };

  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      "yamtrack-redis" = {
        image = "redis:8-alpine";
        volumes = [
          "/var/lib/yamtrack/redis:/data:rw"
        ];
        log-driver = "journald";
        extraOptions = [
          "--log-opt=max-file=1"
          "--log-opt=max-size=10mb"
          "--network=host"
        ];
      };

      "yamtrack" = {
        image = "ghcr.io/dannyvfilms/yamtrack:26.3.5";
        dependsOn = ["yamtrack-redis"];
        environment = {
          TZ = "America/Los_Angeles";
          REDIS_URL = "redis://localhost:6379";
          URLS = "https://yamtrack.adnanshaikh.com";
          REGISTRATION = "False";
        };
        environmentFiles = [
          config.sops.secrets."yamtrack-env".path
        ];
        volumes = [
          "/var/lib/yamtrack/db:/yamtrack/db:rw"
        ];
        log-driver = "journald";
        extraOptions = [
          "--log-opt=max-file=1"
          "--log-opt=max-size=10mb"
          "--network=host"
          "--dns=1.1.1.1,1.0.0.1"
        ];
      };
    };
  };

  services.nginx = {
    virtualHosts = {
      "yamtrack.adnanshaikh.com" = {
        forceSSL = true;
        useACMEHost = "adnanshaikh.com";
        locations."/" = {
          recommendedProxySettings = true;
          proxyPass = "http://127.0.0.1:8000";
        };
      };
    };
  };

  systemd = {
    tmpfiles.rules = [
      "d /var/lib/yamtrack 0755 root root"
      "d /var/lib/yamtrack/db 0755 root root"
      "d /var/lib/yamtrack/redis 0755 root root"
    ];

    targets."podman-compose-yamtrack-root" = {
      unitConfig = {
        Description = "Root target for Yamtrack containers.";
      };
      wantedBy = ["multi-user.target"];
    };

    services = {
      "podman-yamtrack" = {
        after = ["systemd-tmpfiles-setup.service"];
        requires = ["systemd-tmpfiles-setup.service"];
        serviceConfig = {
          Restart = lib.mkOverride 500 "always";
        };
        partOf = [
          "podman-compose-yamtrack-root.target"
        ];
        wantedBy = [
          "podman-compose-yamtrack-root.target"
        ];
      };

      "podman-yamtrack-redis" = {
        after = ["systemd-tmpfiles-setup.service"];
        requires = ["systemd-tmpfiles-setup.service"];
        serviceConfig = {
          Restart = lib.mkOverride 500 "always";
        };
        partOf = [
          "podman-compose-yamtrack-root.target"
        ];
        wantedBy = [
          "podman-compose-yamtrack-root.target"
        ];
      };


    };
  };

  environment.persistence."/nix/persist" = {
    directories = [
      "/var/lib/yamtrack"
    ];
  };
}
