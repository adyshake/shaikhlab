{
  pkgs,
  lib,
  ...
}: {
  environment.systemPackages = with pkgs; [
    efibootmgr
    git
    gptfdisk
    parted
    ventoy
    vim
  ];

  # Ventoy is marked insecure in nixpkgs due to binary-blob concerns; we accept
  # the risk since it's only used to flash NixOS installer USBs from the host.
  # Using the predicate form instead of a pinned version string so routine
  # nixpkgs bumps of ventoy don't keep breaking rebuilds.
  # inspo: https://github.com/ventoy/Ventoy/issues/3224
  nixpkgs.config.allowInsecurePredicate = pkg: lib.getName pkg == "ventoy";
}
