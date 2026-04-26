{
  config,
  pkgs,
  vars,
  ...
}: let
  domain = "git.adnanshaikh.com";
  # Grafana already binds 127.0.0.1:3000, so Forgejo lives on 3001.
  httpPort = 3001;
  # Built-in sshd so we don't have to introduce a `git` system user with an
  # AuthorizedKeysCommand on the host's port-22 sshd. Tailscale-only exposure
  # makes this safe; clones look like:
  #   ssh://git@git.adnanshaikh.com:2222/adnan/<repo>.git
  sshPort = 2222;
in {
  imports = [
    ./_acme.nix
    ./_nginx.nix
  ];

  # Rotated by editing sops + redeploying — the bootstrap unit below refreshes
  # the password from this secret on every activation.
  sops.secrets."forgejo-admin-password" = {
    owner = "forgejo";
    group = "forgejo";
  };

  services.forgejo = {
    enable = true;

    # State on the RAID5 volume so repos and the SQLite DB are protected by
    # mdadm + watched by services/drive-health.nix. Default would be
    # /var/lib/forgejo on the unprotected NVMe.
    stateDir = "/data/forgejo";

    lfs.enable = true;

    # SQLite is the implicit default and is sufficient for a single-user
    # homelab; revisit if usage ever justifies Postgres.

    settings = {
      server = {
        DOMAIN = domain;
        ROOT_URL = "https://${domain}/";
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = httpPort;
        START_SSH_SERVER = true;
        SSH_PORT = sshPort;
        SSH_LISTEN_PORT = sshPort;
        BUILTIN_SSH_SERVER_USER = "git";
        LANDING_PAGE = "login";
      };
      service = {
        DISABLE_REGISTRATION = true;
        REQUIRE_SIGNIN_VIEW = true;
      };
      security = {
        INSTALL_LOCK = true;
        MIN_PASSWORD_LENGTH = 12;
      };
      session.COOKIE_SECURE = true;
      log.LEVEL = "Warn";
    };
  };

  # Bootstrap / reconcile the admin user from sops on every activation.
  # Idempotent: tries change-password first (covers "user already exists,
  # rotate password to current sops value"); falls back to create on first
  # deploy ever (or after wiping /data/forgejo).
  systemd.services.forgejo-admin-bootstrap = {
    description = "Reconcile Forgejo admin user from sops";
    after = ["forgejo.service"];
    requires = ["forgejo.service"];
    wantedBy = ["multi-user.target"];

    serviceConfig = {
      Type = "oneshot";
      User = "forgejo";
      Group = "forgejo";
      RemainAfterExit = true;
    };

    script = let
      forgejoBin = "${config.services.forgejo.package}/bin/forgejo";
      cfg = "/etc/forgejo/app.ini";
      pwFile = config.sops.secrets."forgejo-admin-password".path;
    in ''
      set -eu

      # Wait for forgejo to finish first-run DB init (migrations on Type=simple
      # service). Quick poll instead of an arbitrary sleep.
      for _ in $(seq 1 60); do
        if ${forgejoBin} --config ${cfg} admin user list >/dev/null 2>&1; then
          break
        fi
        sleep 1
      done

      PW=$(cat ${pwFile})

      if ${forgejoBin} --config ${cfg} admin user change-password \
            --username "${vars.userName}" --password "$PW" >/dev/null 2>&1; then
        echo "forgejo: refreshed password for ${vars.userName}"
      else
        ${forgejoBin} --config ${cfg} admin user create \
          --admin \
          --username "${vars.userName}" \
          --email   "${vars.userEmail}" \
          --password "$PW" \
          --must-change-password=false
        echo "forgejo: created admin ${vars.userName}"
      fi
    '';
  };

  services.nginx.virtualHosts."${domain}" = {
    forceSSL = true;
    useACMEHost = "adnanshaikh.com";
    locations."/" = {
      recommendedProxySettings = true;
      proxyPass = "http://127.0.0.1:${toString httpPort}";
      extraConfig = ''
        # Git push of large repos / LFS objects.
        client_max_body_size 512M;
        # Long-running git ops (clone of a big repo, fetch with delta resolution).
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };

  # Built-in SSH server for git push/pull. 80/443 are already opened by
  # services/_acme.nix.
  networking.firewall.allowedTCPPorts = [sshPort];
}
