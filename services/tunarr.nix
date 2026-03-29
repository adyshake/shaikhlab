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
      "tunarr" = {
        image = "chrisbenincasa/tunarr:latest";
        environment = {
          TZ = "America/Los_Angeles";
          LOG_LEVEL = "INFO";
          TUNARR_SERVER_PORT = "8010";
        };
        volumes = [
          "/var/lib/tunarr:/config/tunarr:rw"
          # Share Jellyfin's media path so Tunarr can direct-stream
          "/data/fun:/data/fun:ro"
        ];
        log-driver = "journald";
        extraOptions = [
          "--log-opt=max-file=1"
          "--log-opt=max-size=10mb"
          "--network=host"
        ];
      };
    };
  };

  services.nginx = {
    virtualHosts = {
      "tunarr.adnanshaikh.com" = {
        forceSSL = true;
        useACMEHost = "adnanshaikh.com";
        locations."/" = {
          recommendedProxySettings = true;
          proxyPass = "http://127.0.0.1:8010";
          proxyWebsockets = true;
        };
      };
    };
  };

  systemd = {
    tmpfiles.rules = [
      "d /var/lib/tunarr 0755 root root"
    ];

    targets."podman-compose-tunarr-root" = {
      unitConfig = {
        Description = "Root target for Tunarr containers.";
      };
      wantedBy = ["multi-user.target"];
    };

    services = {
      "podman-tunarr" = {
        after = ["systemd-tmpfiles-setup.service"];
        requires = ["systemd-tmpfiles-setup.service"];
        serviceConfig = {
          Restart = lib.mkOverride 500 "always";
        };
        partOf = [
          "podman-compose-tunarr-root.target"
        ];
        wantedBy = [
          "podman-compose-tunarr-root.target"
        ];
      };
    };
  };

  environment.persistence."/nix/persist" = {
    directories = [
      "/var/lib/tunarr"
    ];
  };
}
