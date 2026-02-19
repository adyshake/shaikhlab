{
  pkgs,
  inputs,
  osConfig,
  ...
}: let
  pkgs-unstable = import inputs.nixpkgs-unstable {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
in {
  home = {
    packages = with pkgs;
      [
        asciinema
        asciiquarium
        cbonsai
        clolcat
        cmatrix
        croc
        curl
        dig
        dust
        dua
        duf
        figlet
        fortune-kind
        gdu
        genact
        imagemagick
        openssl
        jq
        kopia
        neo-cowsay
        pandoc
        pipes-rs
        poppler-utils
        qrencode
        tree
        wget
        ssh-to-age
        sops
        just
        nodejs
      ]
      ++ (
        if builtins.substring 0 3 osConfig.networking.hostName != "svr"
        then [
          # Below packages are for personal machines only; excluded from servers
          # inspo: https://discourse.nixos.org/t/how-to-use-hostname-in-a-path/42612/3
          alejandra
          gnupg1
          ffmpeg
          nixos-rebuild # need for macOS
          pkgs-unstable.gemini-cli
          statix
          zola
        ]
        else [
          # Below packages are for servers only; excluded from personal machines
        ]
      );
  };
}
