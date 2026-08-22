{
  config,
  vars,
  ...
}: {
  boot.kernelParams = ["ip=dhcp"];
  boot.initrd.network = {
    enable = true;
    ssh = {
      enable = true;
      # 26.05 defaults to systemd stage 1; cryptsetup-askpass is gone.
      # Restrict initrd SSH to the password agent. Connect with:
      #   ssh -o RequestTTY=force root@<host>
      authorizedKeys = map (key: ''command="systemctl default" ${key}'')
        config.users.users.${vars.userName}.openssh.authorizedKeys.keys;
      hostKeys = ["/nix/secret/initrd/ssh_host_ed25519_key"];
    };
  };
}
