{
  config,
  ...
}: let
  domain = "photos.adnanshaikh.com";
  mediaDir = "/data/immich";
  pgSchema = config.services.postgresql.package.psqlSchema;
in {
  imports = [
    ./_acme.nix
    ./_nginx.nix
  ];

  # Library (originals + thumbs + Immich's own DB dumps) and Postgres
  # (albums, faces, people) on RAID5+LUKS. Settings are the Nix attrset
  # below — IMMICH_CONFIG_FILE, so the admin UI cannot change them.
  services.immich = {
    enable = true;
    host = "127.0.0.1";
    port = 2283;
    openFirewall = false;
    mediaLocation = mediaDir;
    settings = {
      server = {
        externalDomain = "https://${domain}";
        publicUsers = false;
      };
      newVersionCheck.enabled = false;
      passwordLogin.enabled = true;
      oauth.enabled = false;
      trash = {
        enabled = true;
        days = 30;
      };
      # Config-file default is the compose hostname and would miss the
      # local ML unit (faces, CLIP, OCR).
      machineLearning = {
        enabled = true;
        urls = ["http://localhost:3003"];
        clip.enabled = true;
        facialRecognition.enabled = true;
        duplicateDetection.enabled = true;
        ocr.enabled = true;
      };
      library.scan = {
        enabled = true;
        cronExpression = "0 0 * * *";
      };
      backup.database = {
        enabled = true;
        cronExpression = "0 2 * * *";
        keepLastAmount = 7;
      };
      map.enabled = true;
      reverseGeocoding.enabled = true;
      logging = {
        enabled = true;
        level = "warn";
      };
    };
  };

  services.postgresql.dataDir = "/data/postgresql/${pgSchema}";

  services.redis.servers.immich.logLevel = "warning";

  systemd.tmpfiles.settings.immich-data = {
    ${mediaDir}.d = {
      user = "immich";
      group = "immich";
      mode = "0700";
    };
    "/data/postgresql".d = {
      user = "postgres";
      group = "postgres";
      mode = "0750";
    };
    "/data/postgresql/${pgSchema}".d = {
      user = "postgres";
      group = "postgres";
      mode = "0700";
    };
  };

  systemd.services.immich-server.unitConfig.RequiresMountsFor = [mediaDir];
  systemd.services.postgresql.unitConfig.RequiresMountsFor = ["/data/postgresql"];

  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    useACMEHost = "adnanshaikh.com";
    extraConfig = ''
      client_max_body_size 0;
      proxy_read_timeout 600s;
      proxy_send_timeout 600s;
      send_timeout 600s;
    '';
    locations."/" = {
      recommendedProxySettings = true;
      proxyPass = "http://127.0.0.1:${toString config.services.immich.port}";
      proxyWebsockets = true;
    };
  };

  # ML model weights only; rebuildable, not part of the library.
  environment.persistence."/nix/persist".directories = [
    "/var/cache/immich"
  ];
}
