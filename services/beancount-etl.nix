{
  config,
  pkgs,
  vars,
  ...
}: let
  # Sheet ID lifted from the URL of the user's expense tracker. Not secret —
  # access is gated by service-account sharing on the spreadsheet itself.
  sheetId = "15aHH5iN4BEG0H2WK44pPKVql9OYrq0jeyR8UmUln9wg";
  mainTab = "Expenses";
  historyTab = "History";

  # Forgejo runs on the same host (services/forgejo.nix). We push over HTTPS
  # rather than file:// so Forgejo's pre/post-receive hooks fire and the web
  # UI / commit timeline picks up new pushes properly.
  repoHost = "git.adnanshaikh.com";
  repoPath = "adnan/beancount.git";
  repoUser = vars.userName;

  workDir = "/var/lib/beancount-etl/repo";
  authorName = "Beancount ETL";
  authorEmail = "automation@adnanshaikh.com";

  etlBin = pkgs.writers.writePython3Bin "beancount-etl" {
    libraries = with pkgs.python3Packages; [gspread google-auth pyyaml];
    # The script ships as a single file; flake8's defaults flag a number of
    # cosmetic issues that don't matter here. Disable line length + a few
    # bikeshed rules so the build is reproducible.
    flakeIgnore = ["E501" "E203" "E266" "E402" "W503"];
  } (builtins.readFile ./beancount-etl/import.py);
in {
  # The GCP service-account JSON lives in its own sops-encrypted file (rather
  # than as a string inside secrets.yaml) so it can be encrypted from any
  # machine with the public age key alone — no need to copy the private key
  # off svr1shaikh just to add/rotate this secret. format = "binary" makes
  # sops-nix write the decrypted JSON verbatim to /run/secrets/<name>.
  sops.secrets."beancount-etl-service-account" = {
    owner = "beancount-etl";
    group = "beancount-etl";
    format = "binary";
    sopsFile = ../secrets/beancount-etl-service-account.json;
  };
  # No dedicated PAT: we authenticate git pushes to Forgejo using the
  # declarative admin password (services/forgejo.nix bootstraps it from this
  # same secret). systemd reads the source file as root for LoadCredential
  # before dropping privileges to beancount-etl, so the secret can stay
  # forgejo-owned without us widening its acl.

  users.users.beancount-etl = {
    isSystemUser = true;
    group = "beancount-etl";
    home = "/var/lib/beancount-etl";
  };
  users.groups.beancount-etl = {};

  systemd.services.beancount-etl = {
    description = "Pull complete sheet rows -> Beancount inbox -> Forgejo";
    after = ["forgejo.service" "network-online.target"];
    wants = ["network-online.target"];
    path = [pkgs.git pkgs.openssh];

    environment = {
      BEANCOUNT_ETL_SHEET_ID = sheetId;
      BEANCOUNT_ETL_MAIN_TAB = mainTab;
      BEANCOUNT_ETL_HISTORY_TAB = historyTab;
      BEANCOUNT_ETL_WORK_DIR = workDir;
      BEANCOUNT_ETL_REPO_HOST = repoHost;
      BEANCOUNT_ETL_REPO_PATH = repoPath;
      BEANCOUNT_ETL_REPO_USER = repoUser;
      BEANCOUNT_ETL_AUTHOR_NAME = authorName;
      BEANCOUNT_ETL_AUTHOR_EMAIL = authorEmail;
      # Keep gspread quiet about default-cred discovery noise.
      GOOGLE_APPLICATION_CREDENTIALS = "/run/credentials/beancount-etl.service/service-account";
    };

    serviceConfig = {
      Type = "oneshot";
      User = "beancount-etl";
      Group = "beancount-etl";
      StateDirectory = "beancount-etl";
      StateDirectoryMode = "0750";
      WorkingDirectory = "/var/lib/beancount-etl";
      LoadCredential = [
        "service-account:${config.sops.secrets."beancount-etl-service-account".path}"
        "forgejo-password:${config.sops.secrets."forgejo-admin-password".path}"
      ];
      ExecStart = "${etlBin}/bin/beancount-etl";

      # Hardening — script only needs network out + state dir + credentials.
      NoNewPrivileges = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictNamespaces = true;
      LockPersonality = true;
      ReadWritePaths = ["/var/lib/beancount-etl"];
    };
  };

  systemd.timers.beancount-etl = {
    description = "Periodic Google Sheet -> Beancount inbox import";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "30min";
      Persistent = true;
      Unit = "beancount-etl.service";
    };
  };
}
