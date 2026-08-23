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
in {
  boot.kernelParams = ["ip=dhcp" "rd.luks.options=password-echo=masked"];

  # Both cryptsetup units used to start together, so the TTY agent asked twice
  # before the first passphrase could land in the keyring. Unlock cryptroot
  # first; data then reuses the cached password and stays silent.
  boot.initrd.systemd.services."systemd-cryptsetup@data" = {
    after = ["systemd-cryptsetup@cryptroot.service"];
  };

  boot.initrd.systemd.extraBin.remote-unlock = remoteUnlock;

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
