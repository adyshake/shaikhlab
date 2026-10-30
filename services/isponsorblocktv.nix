{pkgs, ...}: let
  dataDir = "/var/lib/isponsorblocktv";
in {
  users.users.isponsorblocktv = {
    isSystemUser = true;
    group = "isponsorblocktv";
  };
  users.groups.isponsorblocktv = {};

  # Pairing tokens live in config.json. Root is tmpfs, so the dir has to
  # be persisted. Pair from the server, then start the service:
  #   sudo -u isponsorblocktv iSponsorBlockTV -d /var/lib/isponsorblocktv setup-cli
  #   sudo systemctl start isponsorblocktv
  # The code is under YouTube → Settings → Link with TV code.
  environment.persistence."/nix/persist".directories = [
    {
      directory = dataDir;
      user = "isponsorblocktv";
      group = "isponsorblocktv";
      mode = "0700";
    }
  ];

  environment.systemPackages = [pkgs.isponsorblocktv];

  systemd.services.isponsorblocktv = {
    description = "SponsorBlock client for YouTube on TV";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    wantedBy = ["multi-user.target"];
    # The wizard creates this. Until then the unit stays inactive.
    unitConfig.ConditionPathExists = "${dataDir}/config.json";
    serviceConfig = {
      User = "isponsorblocktv";
      Group = "isponsorblocktv";
      ExecStart = "${pkgs.isponsorblocktv}/bin/iSponsorBlockTV -d ${dataDir} start";
      Restart = "on-failure";
    };
  };
}
