{
  config,
  pkgs,
  vars,
  ...
}: let
  remoteUnlock = pkgs.writeScript "remote-unlock" ''
    #!/bin/sh
    echo
    echo "One passphrase unlocks both disks."
    echo "When unlock succeeds this SSH session will close."
    echo
    systemctl default
    status=$?
    echo
    if [ "$status" -eq 0 ]; then
      echo "Unlock succeeded. Switching to the real OS; this SSH session will disconnect."
    else
      echo "Unlock did not finish (systemctl default exited $status)."
    fi
    echo
    # Let the client paint that line before switch-root kills sshd.
    sleep 2
    exit "$status"
  '';

  goodbye = pkgs.writeScript "remote-unlock-goodbye" ''
    #!/bin/sh
    msg="Unlock succeeded. Switching to the real OS; this SSH session will disconnect."
    echo "$msg" >/dev/console 2>/dev/null || true
    for t in /dev/pts/[0-9]*; do
      [ -c "$t" ] || continue
      echo "$msg" >"$t" 2>/dev/null || true
    done
    sleep 1
  '';
in {
  boot.kernelParams = ["ip=dhcp" "rd.luks.options=password-echo=masked"];

  # Both cryptsetup units used to start together, so the TTY agent asked twice
  # before the first passphrase could land in the keyring. Unlock cryptroot
  # first; data then reuses the cached password and stays silent.
  boot.initrd.systemd.services."systemd-cryptsetup@data" = {
    after = ["systemd-cryptsetup@cryptroot.service"];
  };

  boot.initrd.systemd.extraBin = {
    remote-unlock = remoteUnlock;
    remote-unlock-goodbye = goodbye;
  };

  boot.initrd.systemd.services.remote-unlock-goodbye = {
    description = "Announce successful unlock before switch-root";
    wantedBy = ["initrd-switch-root.target"];
    before = ["initrd-switch-root.service"];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = goodbye;
    };
  };

  boot.initrd.network = {
    enable = true;
    ssh = {
      enable = true;
      # 26.05 defaults to systemd stage 1; cryptsetup-askpass is gone.
      # Restrict initrd SSH to the unlock wrapper. Connect with:
      #   ssh -o RequestTTY=force root@<host>
      authorizedKeys = map (key: ''command="/bin/remote-unlock" ${key}'')
        config.users.users.${vars.userName}.openssh.authorizedKeys.keys;
      hostKeys = ["/nix/secret/initrd/ssh_host_ed25519_key"];
    };
  };
}
