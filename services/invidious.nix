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
  # iv-org/smart-ipv6-rotator @ b9cf1f56. One address, Google ranges only.
  rotatorSrc = pkgs.fetchzip {
    url = "https://github.com/iv-org/smart-ipv6-rotator/archive/b9cf1f56c86dc8c8269d1f881c34ff88e43611ff.tar.gz";
    hash = "sha256-iUT9tpScggM+N8aafB+V4/vnEr7UHWp+Ub64QRimA8Q=";
  };
  rotatorPy = pkgs.python3.withPackages (ps: [ps.requests ps.pyroute2]);
  # Picks the on-link /64 on the IPv6 default route. --not-preferred keeps
  # that address off the host's default source selection; the script still
  # installs prefsrc routes for Google's ranges.
  rotateGoogleV6 = pkgs.writeShellScript "invidious-rotate-ipv6" ''
    set -eu
    dev=$(${pkgs.iproute2}/bin/ip -6 route show default | ${pkgs.gawk}/bin/awk '/^default/ {print $5; exit}')
    if [ -z "$dev" ]; then
      echo "invidious ipv6 rotator: no IPv6 default route" >&2
      exit 1
    fi
    prefix=$(${pkgs.python3}/bin/python3 -c '
import ipaddress, subprocess, sys
dev = sys.argv[1]
out = subprocess.check_output(["${pkgs.iproute2}/bin/ip", "-6", "-o", "addr", "show", "dev", dev, "scope", "global"], text=True)
nets = []
for line in out.splitlines():
    iface = ipaddress.IPv6Interface(line.split()[3])
    if iface.network.prefixlen == 64 and str(iface.network) not in nets:
        nets.append(str(iface.network))
if not nets:
    raise SystemExit("no global /64 on %s" % dev)
print(nets[0])
' "$dev")
    echo "invidious ipv6 rotator: using $prefix on $dev" >&2
    export PYTHONPATH=${rotatorSrc}
    exec ${rotatorPy}/bin/python ${rotatorSrc}/smart-ipv6-rotator.py run \
      --ipv6range="$prefix" \
      --not-preferred \
      --log-level INFO
  '';
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
      # Companion rotates YouTube onto a fresh IPv6. Keep this app on v6
      # too, or playback URLs are minted for an address the proxy is not using.
      force_resolve = "ipv6";
      # stateVersion is 23.11, which would pair user "kemal" with database
      # "invidious" and fail local provisioning.
      db.user = "invidious";
      db.dbname = "invidious";
      invidious_companion = [
        {private_url = "http://127.0.0.1:8282/companion";}
      ];
      captcha_enabled = false;
      popular_enabled = false;
      admins = [vars.userName];
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
    # Host network, not podman0. The rotator installs routes on the host;
    # the bridge would still NAT YouTube out as the house IPv4.
    networks = ["host"];
    environment = {
      HOST = "127.0.0.1";
    };
    environmentFiles = [companionEnv];
    volumes = ["${cacheDir}:/var/tmp/youtubei.js:rw"];
    extraOptions = [
      "--read-only"
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges"
      "--user=10001:10001"
    ];
  };

  systemd.services.smart-ipv6-rotator = {
    description = "Rotate the IPv6 source used for YouTube";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = rotateGoogleV6;
    };
  };

  systemd.timers.smart-ipv6-rotator = {
    description = "Rotate the YouTube IPv6 source twice a day";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnUnitActiveSec = "12h";
      AccuracySec = "15min";
      Persistent = true;
    };
  };

  systemd.services.podman-invidious-companion = {
    after = ["invidious.service" "smart-ipv6-rotator.service"];
    wants = ["smart-ipv6-rotator.service"];
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

  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    useACMEHost = "adnanshaikh.com";
    locations."/" = {
      recommendedProxySettings = true;
      proxyPass = "http://127.0.0.1:3010";
      extraConfig = ''
        proxy_buffering off;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };
}
