{
  config,
  ...
}: let
  domain = "ntfy.adnanshaikh.com";
  ntfyUser = "arr";
  ntfyTopic = "media";
  secretMount = "/run/ntfy-secret";
in {
  imports = [
    ./_acme.nix
    ./_nginx.nix
    ./_cloudflared.nix
    ./../modules/nixos/public-jail.nix
  ];

  # Host decrypts; bind-mounted into the jail. 0444 because nspawn
  # privateUsers maps guest root to a high host UID that cannot read 0400.
  sops.secrets."ntfy-secret" = {
    mode = "0444";
    restartUnits = ["container@ntfy.service"];
  };

  shaikhlab.publicJails.ntfy = {
    enable = true;
    id = 11;
    guestPort = 2586;
    proxyPort = 12586;
    domain = domain;
    public = true;
    memoryMax = "256M";
    tmpfsSize = "16M";
    maxBodySize = "256k";
    proxyWebsockets = true;
    proxyReadTimeout = "10m";
    proxySendTimeout = "10m";
    sendTimeout = "10m";
    allowEgress = true;
    rateLimit = {
      rate = "60r/m";
      burst = 80;
      connections = 32;
      globalRate = "10r/s";
      globalBurst = 80;
    };
    bindMounts = {
      ${secretMount} = {
        hostPath = config.sops.secrets."ntfy-secret".path;
        isReadOnly = true;
      };
    };
    guest = {
      config,
      pkgs,
      ...
    }: {
      services.ntfy-sh = {
        enable = true;
        settings = {
          base-url = "https://${domain}";
          listen-http = "0.0.0.0:2586";
          behind-proxy = true;
          auth-file = "/var/lib/ntfy-sh/user.db";
          auth-default-access = "deny-all";
          # iOS: jail may HTTPS to ntfy.sh only (host FORWARD + NAT).
          # https://docs.ntfy.sh/config/#ios-instant-notifications
          upstream-base-url = "https://ntfy.sh";
        };
      };

      systemd.services.ntfy-sh.serviceConfig = {
        LoadCredential = "ntfy-pw:${secretMount}";
        ExecStartPost = let
          bootstrap = pkgs.writeShellScript "ntfy-bootstrap" ''
            set -eu
            NTFY=${config.services.ntfy-sh.package}/bin/ntfy
            export NTFY_AUTH_FILE=/var/lib/ntfy-sh/user.db
            export NTFY_AUTH_DEFAULT_ACCESS=deny-all

            PW=$(cat "$CREDENTIALS_DIRECTORY/ntfy-pw")

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
    };
  };
}
