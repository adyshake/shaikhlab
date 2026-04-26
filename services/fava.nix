{
  config,
  pkgs,
  lib,
  vars,
  ...
}: let
  domain = "beancount.adnanshaikh.com";
  # Bind to 127.0.0.1; nginx terminates TLS. 5050 to keep clear of the
  # 5000/5001 range commonly used by other dev tooling.
  httpPort = 5050;

  # Working-copy mirror of the bare Forgejo repo. Lives on the NVMe rather
  # than /data because the source of truth is Forgejo's bare repo (also on
  # /data) — duplicating to RAID buys nothing.
  ledgerDir = "/var/lib/fava/ledger";
  ledgerEntry = "${ledgerDir}/total/journal.beancount";

  # The bare repo Forgejo writes pushes to. We clone over file:// to avoid
  # any auth or networking — fava just needs filesystem read on this path,
  # handled via group membership below.
  forgejoBareRepo = "/data/forgejo/repositories/adnan/beancount.git";

  # fava-dashboards isn't in nixpkgs; package straight from PyPI.
  # 1.2.3 is the latest stable in the 1.x line (2.x is still beta).
  fava-dashboards = pkgs.python3Packages.buildPythonPackage rec {
    pname = "fava_dashboards";
    version = "1.2.3";
    src = pkgs.fetchPypi {
      inherit pname version;
      sha256 = "bd3a578cac945d399cb9c1133ee2b24020d1741aa98fea41e8e5331de8a8024e";
    };
    format = "pyproject";
    nativeBuildInputs = with pkgs.python3Packages; [hatchling hatch-vcs];
    propagatedBuildInputs = with pkgs.python3Packages; [fava];
    pythonImportsCheck = ["fava_dashboards"];
    doCheck = false;
  };

  # Override fava so the extension is on the same PYTHONPATH the wrapper
  # script uses. Keeps the existing `fava` binary location (so service
  # ExecStart still reads naturally) but adds dashboards as a dep.
  favaWithExtensions = pkgs.fava.overridePythonAttrs (old: {
    propagatedBuildInputs = (old.propagatedBuildInputs or []) ++ [fava-dashboards];
  });
in {
  imports = [
    ./_acme.nix
    ./_nginx.nix
  ];

  users.users.fava = {
    isSystemUser = true;
    group = "fava";
    # forgejo group lets us read the bare repo (mode 0750 forgejo:forgejo).
    extraGroups = ["forgejo"];
    home = "/var/lib/fava";
  };
  users.groups.fava = {};

  # Reconcile the working copy from the Forgejo bare repo. Idempotent:
  # clone on first run, fast-forward thereafter. `reset --hard origin/main`
  # rather than `pull` so any accidental local edits never block sync.
  systemd.services.fava-sync = {
    description = "Sync Fava ledger working copy from Forgejo bare repo";
    after = ["forgejo.service"];
    path = [pkgs.git];

    serviceConfig = {
      Type = "oneshot";
      User = "fava";
      Group = "fava";
      StateDirectory = "fava";
      StateDirectoryMode = "0750";
    };

    script = ''
      set -eu

      if [ ! -d ${ledgerDir}/.git ]; then
        git clone --branch main "file://${forgejoBareRepo}" ${ledgerDir}
        echo "fava-sync: cloned ledger from ${forgejoBareRepo}"
      else
        git -C ${ledgerDir} fetch --quiet origin
        git -C ${ledgerDir} reset --hard --quiet origin/main
        echo "fava-sync: fast-forwarded to $(git -C ${ledgerDir} rev-parse --short HEAD)"
      fi
    '';
  };

  # 5-minute pull cadence; `OnBootSec` ensures the very first sync runs
  # shortly after boot so fava.service has files to read on cold start.
  systemd.timers.fava-sync = {
    description = "Periodic ledger sync from Forgejo";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "5min";
      Unit = "fava-sync.service";
    };
  };

  systemd.services.fava = {
    description = "Fava (Beancount web UI)";
    after = ["fava-sync.service" "network.target"];
    wants = ["fava-sync.service"];
    wantedBy = ["multi-user.target"];

    serviceConfig = {
      User = "fava";
      Group = "fava";
      ExecStart = "${favaWithExtensions}/bin/fava --host 127.0.0.1 --port ${toString httpPort} ${ledgerEntry}";
      Restart = "on-failure";
      RestartSec = "10s";
      # Light hardening — fava only needs to read the ledger.
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadOnlyPaths = [ledgerDir];
    };
  };

  services.nginx.virtualHosts."${domain}" = {
    forceSSL = true;
    useACMEHost = "adnanshaikh.com";
    locations."/" = {
      recommendedProxySettings = true;
      proxyPass = "http://127.0.0.1:${toString httpPort}";
    };
  };
}
