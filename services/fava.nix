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
  #
  # Pinned to 1.2.0 — last release whose declared lower bound (`fava>=1.26.1`)
  # is satisfied by nixpkgs nixos-25.11's fava 1.30.7. Releases 1.2.1+ bump
  # the floor to `fava>=1.30.8`, which would force pulling fava from
  # nixpkgs-unstable or building it ourselves. Revisit when nixos-26.05
  # ships or if a missing 1.2.x feature is actually needed.
  fava-dashboards = pkgs.python3Packages.buildPythonPackage rec {
    pname = "fava_dashboards";
    version = "1.2.0";
    src = pkgs.fetchPypi {
      inherit pname version;
      sha256 = "86f85f52dd5071ab8e2de4569060a5845e2dc1c3f2b890e0f10cfc5eb4377399";
    };
    format = "pyproject";
    nativeBuildInputs = with pkgs.python3Packages; [hatchling hatch-vcs];
    propagatedBuildInputs = with pkgs.python3Packages; [fava pyyaml];
    pythonImportsCheck = ["fava_dashboards"];
    doCheck = false;
  };

  # Single Python env with both fava and the dashboards extension.
  # `python3.withPackages` dedupes by store path, so the fava propagated
  # from fava-dashboards collapses with `ps.fava` here — avoiding the
  # duplicate-package conflict that `pkgs.fava.overridePythonAttrs` hits.
  favaEnv = pkgs.python3.withPackages (ps: [ps.fava fava-dashboards]);
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
      ExecStart = "${favaEnv}/bin/fava --host 127.0.0.1 --port ${toString httpPort} ${ledgerEntry}";
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
