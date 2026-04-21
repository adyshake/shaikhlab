{
  config,
  pkgs,
  ...
}: let
  domain = "ntfy.adnanshaikh.com";
  # Single shared user that both Radarr and Sonarr authenticate as when
  # publishing, and that you enter on the phone when subscribing.
  ntfyUser = "arr";
  # Topic the phone subscribes to. Arbitrary string; must match what Radarr/Sonarr
  # publish to (configured in services/nixarr.nix).
  ntfyTopic = "media";
in {
  # Public exposure of ntfy.adnanshaikh.com is configured centrally in
  # services/_cloudflared.nix (which is imported by services/nixarr.nix).
  imports = [
    ./_acme.nix
    ./_nginx.nix
  ];

  sops.secrets."ntfy-secret" = {};

  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://${domain}";
      listen-http = "127.0.0.1:2586";
      behind-proxy = true;

      # Require explicit auth for every topic. Combined with the ACL set below,
      # only the "arr" user can publish/subscribe to the "media" topic.
      auth-file = "/var/lib/ntfy-sh/user.db";
      auth-default-access = "deny-all";

      # iOS self-hosted servers cannot deliver instant pushes directly; messages
      # are relayed through the public ntfy.sh instance, which forwards a
      # poll-request via APNs. Phone then fetches the real message from our
      # server. This is free and documented upstream:
      # https://docs.ntfy.sh/config/#ios-instant-notifications
      upstream-base-url = "https://ntfy.sh";
    };
  };

  # Idempotently create the "arr" user and ACL after the ntfy-sh server starts.
  # Runs inside the ntfy-sh unit so it inherits the same DynamicUser and has
  # write access to StateDirectory (/var/lib/ntfy-sh/user.db).
  # LoadCredential copies the sops secret into the unit's private credential
  # directory so the DynamicUser can read the password without chmodding secrets.
  systemd.services.ntfy-sh.serviceConfig = {
    LoadCredential = "ntfy-pw:${config.sops.secrets."ntfy-secret".path}";
    ExecStartPost = let
      bootstrap = pkgs.writeShellScript "ntfy-bootstrap" ''
        set -eu
        NTFY=${config.services.ntfy-sh.package}/bin/ntfy
        export NTFY_AUTH_FILE=/var/lib/ntfy-sh/user.db
        export NTFY_AUTH_DEFAULT_ACCESS=deny-all

        PW=$(cat "$CREDENTIALS_DIRECTORY/ntfy-pw")

        # Wait for ntfy to initialize the SQLite auth DB on first start.
        for _ in $(seq 1 40); do
          [ -s "$NTFY_AUTH_FILE" ] && break
          sleep 0.25
        done

        if $NTFY user list 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q "^user ${ntfyUser} "; then
          printf '%s\n%s\n' "$PW" "$PW" | $NTFY user change-pass ${ntfyUser} >/dev/null
        else
          printf '%s\n%s\n' "$PW" "$PW" | $NTFY user add ${ntfyUser}
        fi
        $NTFY access ${ntfyUser} '${ntfyTopic}' rw
      '';
    in ["${bootstrap}"];
  };

  services.nginx.virtualHosts."${domain}" = {
    forceSSL = true;
    useACMEHost = "adnanshaikh.com";
    locations."/" = {
      recommendedProxySettings = true;
      proxyPass = "http://127.0.0.1:2586";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_buffering off;
        proxy_request_buffering off;
        client_max_body_size 100M;
        # Subscriptions are long-lived streams/websockets.
        proxy_read_timeout 10m;
        proxy_send_timeout 10m;
      '';
    };
  };

  # No environment.persistence entry: /var/lib/ntfy-sh is intentionally
  # ephemeral. The auth user + ACL is recreated on every boot by the
  # ExecStartPost bootstrap above, sourced from the ntfy-secret sops secret.
  # The only cost is losing the ~12h message cache across reboots.
}
