{
  config,
  pkgs,
  vars,
  ...
}: let
  domain = "drive.adnanshaikh.com";
  dataRoot = "/data/nextcloud";
in {
  imports = [
    ./_acme.nix
    ./_nginx.nix
  ];

  # Files live at /data/nextcloud/data/<user>/files on RAID+LUKS.
  # Same Postgres cluster as Immich (/data/postgresql). Redis is
  # nextcloud-only. Tailscale via nginx 80/443 — not a public jail.
  sops.secrets."nextcloud-admin-password" = {
    format = "binary";
    sopsFile = ./../secrets/nextcloud-admin-password;
    mode = "0400";
    restartUnits = ["nextcloud-setup.service" "nextcloud-admin-password.service"];
  };

  services.nextcloud = {
    enable = true;
    hostName = domain;
    https = true;
    # stateVersion is 23.11 and would otherwise pick Nextcloud 31.
    package = pkgs.nextcloud32;
    home = dataRoot;
    datadir = dataRoot;
    maxUploadSize = "8G";
    appstoreEnable = false;
    extraApps = {};
    extraAppsEnable = false;
    configureRedis = true;
    database.createLocally = true;
    config = {
      dbtype = "pgsql";
      adminuser = vars.userName;
      adminpassFile = config.sops.secrets."nextcloud-admin-password".path;
    };
    settings = {
      overwriteprotocol = "https";
      trusted_proxies = ["127.0.0.1" "::1"];
      default_phone_region = "US";
      skeletondirectory = "";
      "profile.enabled" = false;
    };
  };

  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    useACMEHost = "adnanshaikh.com";
  };

  systemd.services.nextcloud-setup.unitConfig.RequiresMountsFor = [dataRoot];
  systemd.services.phpfpm-nextcloud.unitConfig.RequiresMountsFor = [dataRoot];

  # nextcloud-setup only writes the admin password on first install.
  systemd.services.nextcloud-admin-password = {
    description = "Reconcile Nextcloud admin password from sops";
    after = ["nextcloud-setup.service"];
    requires = ["nextcloud-setup.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      export OC_PASS="$(cat ${config.sops.secrets."nextcloud-admin-password".path})"
      ${config.services.nextcloud.occ}/bin/nextcloud-occ user:resetpassword --password-from-env ${vars.userName}
    '';
  };
}
