{
  config,
  lib,
  pkgs,
  vars,
  ...
}: let
  domain = "invidious.adnanshaikh.com";
  stateDir = "/var/lib/invidious";
  cacheDir = "${stateDir}/companion-cache";
  companionKey = "${stateDir}/companion_key";
  companionEnv = "${stateDir}/companion.env";
  companionSettings = "${stateDir}/companion.json";
in {
  imports = [
    ./_nginx.nix
  ];

  # The module turns on DynamicUser, which wants to move this directory
  # under /var/lib/private. It is a bind mount, so that move fails.
  users.users.invidious = {
    isSystemUser = true;
    group = "invidious";
    home = stateDir;
  };
  users.groups.invidious = {};

  # The Crystal app serves the website and the API. Companion is what
  # actually fetches playable streams; the old sig helper no longer works.
  # Companion publishes no version tags, so this tracks Quay's latest.
  services.invidious = {
    enable = true;
    address = "127.0.0.1";
    # 3000 is Grafana, 3001 is Forgejo.
    port = 3010;
    domain = domain;

    settings = {
      https_only = true;
      external_port = 443;
      # stateVersion is 23.11, which would pair user "kemal" with database
      # "invidious" and fail local provisioning.
      db.user = "invidious";
      db.dbname = "invidious";
      invidious_companion = [
        {private_url = "http://127.0.0.1:8282/companion";}
      ];
      captcha_enabled = false;
      admins = [vars.userName];
      # The Popular tab is a page of its own. Trending has no matching
      # switch, so nginx sends both feeds back to search.
      popular_enabled = false;
      # Blank homepage is the search page. An empty feed menu leaves both
      # slots on Search; the preferences form drops blank entries.
      default_user_preferences = {
        continue_autoplay = false;
        related_videos = false;
        search_privacy = true;
        default_home = "";
        feed_menu = [];
      };
    };

    extraSettingsFile = companionSettings;
  };

  # Companion key is 16 characters and must match on both sides. It stays
  # out of the store. Invidious generates its own hmac key beside this.
  systemd.services.invidious = {
    unitConfig.RequiresMountsFor = [stateDir];
    serviceConfig.DynamicUser = lib.mkForce false;
    preStart = lib.mkAfter ''
      if [[ ! -e ${companionKey} ]]; then
        ${pkgs.pwgen}/bin/pwgen 16 1 | tr -d '\n' > ${companionKey}
        chmod 0600 ${companionKey}
      fi
      key="$(tr -d '\n' < ${companionKey})"
      printf 'SERVER_SECRET_KEY=%s\n' "$key" > ${companionEnv}
      chmod 0600 ${companionEnv}
      ${pkgs.jq}/bin/jq -n --arg key "$key" '{invidious_companion_key: $key}' > ${companionSettings}
      chmod 0600 ${companionSettings}
    '';
  };

  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";
  virtualisation.oci-containers.containers.invidious-companion = {
    image = "quay.io/invidious/invidious-companion:latest";
    ports = ["127.0.0.1:8282:8282"];
    environmentFiles = [companionEnv];
    volumes = ["${cacheDir}:/var/tmp/youtubei.js:rw"];
    extraOptions = [
      "--read-only"
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges"
      "--user=10001:10001"
    ];
  };

  systemd.services.podman-invidious-companion = {
    after = ["invidious.service"];
    unitConfig.RequiresMountsFor = [stateDir];
    serviceConfig.ExecStartPre = lib.mkAfter [
      "${pkgs.coreutils}/bin/install -d -m 0750 -o 10001 -g 10001 ${cacheDir}"
    ];
  };

  # hmac key, companion key, and the companion's player cache. Root is tmpfs.
  # Postgres for this app lives with the existing cluster on /data.
  # Container images live under /var/lib/containers, which is also tmpfs.
  environment.persistence."/nix/persist".directories = [
    stateDir
    "/var/lib/containers"
  ];

  # Companion's outbound path is podman0. Without this, NixOS drops
  # the YouTube requests it is here to make.
  networking.firewall.trustedInterfaces = ["podman0"];

  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    useACMEHost = "adnanshaikh.com";
    # /search, not /. A saved homepage of Popular would otherwise
    # bounce between the feed and the front page.
    locations."= /feed/popular".return = "302 /search";
    locations."= /feed/trending".return = "302 /search";
    locations."/" = {
      recommendedProxySettings = true;
      proxyPass = "http://127.0.0.1:3010";
      extraConfig = ''
        proxy_buffering off;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Accept-Encoding "";
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;

        # A saved preference can still ask for these tabs. Hide the links
        # and drop the options so they cannot be turned back on.
        gzip on;
        gzip_types text/html;
        sub_filter_once off;
        sub_filter_types text/html;
        sub_filter 'href="/feed/popular"' 'href="/" hidden';
        sub_filter 'href="/feed/trending"' 'href="/" hidden';
        sub_filter '<option value="Popular"  selected >Popular</option>' ''';
        sub_filter '<option value="Popular" >Popular</option>' ''';
        sub_filter '<option value="Trending"  selected >Trending</option>' ''';
        sub_filter '<option value="Trending" >Trending</option>' ''';
      '';
    };
  };
}
