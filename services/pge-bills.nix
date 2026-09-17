{
  config,
  lib,
  pkgs,
  vars,
  ...
}: let
  # Encrypt with `sops -e -i secrets/pge-credentials`. JSON:
  #   {"username":"<pge login>","password":"<pge password>"}
  # Optional overrides: imap_host, imap_user, imap_password, imap_port.
  # The timer stays off until this file exists so a missing secret does
  # not break deploy. MFA codes must be emailed to vars.userEmail.
  credsFile = ./../secrets/pge-credentials;
  hasCreds = builtins.pathExists credsFile;
  archiveDir = "/data/pge-bills";
  pythonEnv = pkgs.python3.withPackages (ps: [ps.playwright]);
in {
  imports = [./mail.nix];

  config = lib.mkIf hasCreds {
    sops.secrets."pge-credentials" = {
      format = "binary";
      sopsFile = credsFile;
      mode = "0400";
      restartUnits = ["pge-bills.service"];
    };

    users.users.pge-bills = {
      isSystemUser = true;
      group = "pge-bills";
      home = "/var/lib/pge-bills";
    };
    users.groups.pge-bills = {};

    systemd.tmpfiles.settings.pge-bills = {
      ${archiveDir}.d = {
        user = "pge-bills";
        group = "pge-bills";
        mode = "0700";
      };
    };

    environment.persistence."/nix/persist".directories = [
      {
        directory = "/var/lib/pge-bills";
        user = "pge-bills";
        group = "pge-bills";
        mode = "0700";
      }
    ];

    systemd.services.pge-bills = {
      description = "Download official PG&E bill PDFs";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      unitConfig.RequiresMountsFor = [archiveDir];

      environment = {
        PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
        PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "1";
        HOME = "/var/lib/pge-bills";
        XDG_CACHE_HOME = "/var/lib/pge-bills/cache";
      };

      serviceConfig = {
        Type = "oneshot";
        User = "pge-bills";
        Group = "pge-bills";
        StateDirectory = "pge-bills";
        StateDirectoryMode = "0700";
        WorkingDirectory = "/var/lib/pge-bills";
        TimeoutStartSec = "15min";
        MemoryMax = "2G";
        LoadCredential = [
          "pge-credentials:${config.sops.secrets."pge-credentials".path}"
          "mxroute-smtp-password:${config.sops.secrets."mxroute-smtp-password".path}"
        ];
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [archiveDir];
      };

      script = ''
        set -eu
        exec ${pythonEnv}/bin/python3 ${./pge-bills/fetch.py} \
          --credentials "$CREDENTIALS_DIRECTORY/pge-credentials" \
          --imap-password-file "$CREDENTIALS_DIRECTORY/mxroute-smtp-password" \
          --imap-user ${lib.escapeShellArg vars.userEmail} \
          --smtp-user ${lib.escapeShellArg vars.userEmail} \
          --smtp-password-file "$CREDENTIALS_DIRECTORY/mxroute-smtp-password" \
          --state-dir /var/lib/pge-bills \
          --output-dir ${archiveDir} \
          --mail-to ${lib.escapeShellArg vars.userEmail} \
          --mail-from ${lib.escapeShellArg vars.userEmail} \
          --hostname ${lib.escapeShellArg config.networking.hostName}
      '';
    };

    # Weekly keeps the remembered-device session under PG&E's 90-day idle
    # MFA trigger and picks up the monthly statement within a few days.
    systemd.timers.pge-bills = {
      description = "Weekly PG&E bill PDF download";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "Mon *-*-* 08:15:00";
        OnBootSec = "10min";
        Persistent = true;
        RandomizedDelaySec = "15m";
        Unit = "pge-bills.service";
      };
    };
  };
}
