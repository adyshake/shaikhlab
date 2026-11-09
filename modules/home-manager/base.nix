{
  lib,
  pkgs,
  vars,
  osConfig,
  inputs,
  ...
}: let
  # YouTube extractors break often; stable yt-dlp trips the 90-day stale
  # warning. Unstable tracks new releases more closely.
  pkgs-unstable = import inputs.nixpkgs-unstable {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
in {
  imports = [
    ./_packages.nix
    ./_zsh.nix
  ];

  home = {
    username = vars.userName;
    homeDirectory = lib.mkMerge [
      (lib.mkIf pkgs.stdenv.isLinux "/home/${vars.userName}")
      (lib.mkIf pkgs.stdenv.isDarwin "/Users/${vars.userName}")
    ];
    # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
    stateVersion = "23.11";
    sessionVariables = lib.mkIf pkgs.stdenv.isDarwin {
      SOPS_AGE_KEY_FILE = "$HOME/.config/sops/age/keys.txt";
    };
  };

  programs = {
    helix = {
      enable = true;
      defaultEditor = true;
      settings = {
        theme = "dark_high_contrast";
      };
    };
    fzf = {
      enable = true;
      enableZshIntegration = true;
    };
    tealdeer = {
      enable = true;
      settings.updates.auto_update = true;
    };
    direnv = {
      enable = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };
    bat.enable = true;
    btop.enable = true;
    gallery-dl.enable = true;
    fastfetch.enable = true;
    htop.enable = true;
    lsd.enable = true;
    nh.enable = true;
    vim = {
      enable = true;
      settings = {
        # Absolute line number on the current line.
        number = true;
        # Relative line numbers everywhere else, so 5j jumps five lines.
        relativenumber = true;
        # Indent with spaces instead of a tab character.
        expandtab = true;
        # A literal tab displays as 2 columns.
        tabstop = 2;
        # Each indent or outdent moves 2 spaces.
        shiftwidth = 2;
        # Search ignores capitalization.
        ignorecase = true;
        # A capital letter in the pattern makes that search case-sensitive.
        smartcase = true;
      };
      extraConfig = ''
        " Highlight matches for the last search. Ctrl-L clears them.
        set hlsearch
        " Leave click-and-drag selection to the terminal.
        set mouse=
      '';
    };
    yt-dlp = {
      enable = true;
      package = pkgs-unstable.yt-dlp;
      # 2026.07.04 still defaults to android_vr, whose media URLs 403.
      # 2026.08.19 drops that client; until nixpkgs ships it, force
      # web_embedded (high-quality) with android as a progressive fallback.
      settings =
        {
          extractor-args = "youtube:player_client=web_embedded,android";
        }
        // lib.optionalAttrs pkgs.stdenv.isDarwin {
          # macOS Gatekeeper quarantines CLI downloads; strip it off the
          # final file so Finder/QuickTime don't block playback.
          # Quotes are required: home-manager writes this as a raw line,
          # and yt-dlp's config parser splits on unquoted spaces.
          exec = ''"after_move:xattr -c %(filepath)q"'';
        };
    };
  };

  # Nicely reload system units when changing configs
  # Self-note: nix-darwin seems to luckily ignore this setting
  systemd.user.startServices = "sd-switch";
}
