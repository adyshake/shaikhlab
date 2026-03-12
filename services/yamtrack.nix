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
          "--network=yamtrack-net"
        ];
      };

      "yamtrack" = {
        image = "ghcr.io/dannyvfilms/yamtrack:v26.3.5";
        dependsOn = ["yamtrack-redis"];
        environment = {
          TZ = "America/Chicago";
          REDIS_URL = "redis://yamtrack-redis:6379";
          URLS = "https://yamtrack.adnanshaikh.com";
          REGISTRATION = "False";
        };
        environmentFiles = [
          config.sops.secrets."yamtrack-env".path
        ];
        volumes = [
          "/var/lib/yamtrack/db:/yamtrack/db:rw"
        ];
        ports = ["8000:8000"];
        log-driver = "journald";
        extraOptions = [
          "--log-opt=max-file=1"
          "--log-opt=max-size=10mb"
          "--network=yamtrack-net"
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

      "create-yamtrack-network" = {
        description = "Create Podman network for Yamtrack";
        after = ["podman.service"];
        wantedBy = ["podman-yamtrack.service" "podman-yamtrack-redis.service"];
        before = ["podman-yamtrack.service" "podman-yamtrack-redis.service"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.podman}/bin/podman network create yamtrack-net --ignore";
        };
      };
    };
  };

  environment.persistence."/nix/persist" = {
    directories = [
      "/var/lib/yamtrack"
    ];
  };
}
