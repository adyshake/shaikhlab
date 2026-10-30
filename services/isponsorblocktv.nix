{
  pkgs,
  inputs,
  ...
}: let
  dataDir = "/var/lib/isponsorblocktv";
  # nixos-26.05 is still on 2.6.1, which predates YouTube's new screen-id
  # format. Unstable tracks the packaged client (currently 2.10).
  pkg = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.isponsorblocktv;

  # Screen ids are lounge pairing tokens. The wizard writes them into
  # config.json; they are not something we can declare up front.
  hasDevices = "${pkgs.jq}/bin/jq -e '.devices | type == \"array\" and length > 0' ${dataDir}/config.json >/dev/null 2>&1";

  setup = pkgs.writeShellScriptBin "isponsorblocktv-setup" ''
    set -eu
    if [ "$(id -u)" -ne 0 ]; then
      exec ${pkgs.sudo}/bin/sudo "$0" "$@"
    fi

    ${pkgs.systemd}/bin/systemctl stop isponsorblocktv.service || true
    ${pkgs.systemd}/bin/systemd-tmpfiles --create

    set +e
    ${pkgs.sudo}/bin/sudo -u isponsorblocktv -H \
      env HOME=${dataDir} iSPBTV_data_dir=${dataDir} \
      ${pkg}/bin/iSponsorBlockTV -d ${dataDir} setup-cli
    status=$?
    set -e

    if ${hasDevices}; then
      ${pkgs.systemd}/bin/systemctl start isponsorblocktv.service
    else
      echo "isponsorblocktv: no paired devices; service left stopped." >&2
    fi
    exit "$status"
  '';
in {
  users.users.isponsorblocktv = {
    isSystemUser = true;
    group = "isponsorblocktv";
    home = dataDir;
  };
  users.groups.isponsorblocktv = {};

  systemd.tmpfiles.settings.isponsorblocktv = {
    ${dataDir}.d = {
      user = "isponsorblocktv";
      group = "isponsorblocktv";
      mode = "0700";
    };
  };

  # Pairing survives reboot on this tmpfs-root host. A wiped array means
  # running `isponsorblocktv-setup` again (YouTube → Settings → Link with TV code).
  environment.persistence."/nix/persist".directories = [
    {
      directory = dataDir;
      user = "isponsorblocktv";
      group = "isponsorblocktv";
      mode = "0700";
    }
  ];

  environment.systemPackages = [setup];

  systemd.services.isponsorblocktv = {
    description = "SponsorBlock client for YouTube on TV";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    wantedBy = ["multi-user.target"];
    unitConfig.ConditionPathExists = "${dataDir}/config.json";

    environment = {
      HOME = dataDir;
      iSPBTV_data_dir = dataDir;
    };

    # Stays idle until setup has paired at least one TV. Runtime is outbound
    # lounge API only; discovery is not required after the link code is used.
    script = ''
      set -eu
      if ! ${hasDevices}; then
        echo "isponsorblocktv: no paired devices in ${dataDir}/config.json; run isponsorblocktv-setup" >&2
        exit 0
      fi
      exec ${pkg}/bin/iSponsorBlockTV -d ${dataDir} start
    '';

    serviceConfig = {
      User = "isponsorblocktv";
      Group = "isponsorblocktv";
      StateDirectory = "isponsorblocktv";
      StateDirectoryMode = "0700";
      WorkingDirectory = dataDir;
      Restart = "on-failure";
      RestartSec = "5s";
      UMask = "0077";
      NoNewPrivileges = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
      MemoryMax = "512M";
    };
  };
}
