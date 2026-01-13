{
  lib,
  pkgs,
  ...
}: {
  programs.alacritty = {
    enable = true;
    settings = {
      colors = {
        bright = {
          black = "#737475";
          blue = "#959697";
          cyan = "#b15928";
          green = "#2e2f30";
          magenta = "#dadbdc";
          red = "#e6550d";
          white = "#fcfdfe";
          yellow = "#515253";
        };
        cursor = {
          cursor = "#b7b8b9";
          text = "#0c0d0e";
        };
        normal = {
          black = "#0c0d0e";
          blue = "#3182bd";
          cyan = "#80b1d3";
          green = "#31a354";
          magenta = "#756bb1";
          red = "#e31a1c";
          white = "#b7b8b9";
          yellow = "#dca060";
        };
        primary = {
          background = "#0c0d0e";
          foreground = "#b7b8b9";
        };
      };

      cursor = {
        unfocused_hollow = true;
        style.blinking = "On";
      };

      window = {
        dimensions = {
          lines = 30;
          columns = 150;
        };
        decorations = lib.mkMerge [
          (lib.mkIf pkgs.stdenv.isLinux "Full")
          (lib.mkIf pkgs.stdenv.isDarwin "transparent")
        ];
        dynamic_padding = true;
        padding = {
          x = 30;
          y = 30;
        };
      };

      font = {
        size = lib.mkMerge [
          (lib.mkIf pkgs.stdenv.isLinux 12)
          (lib.mkIf pkgs.stdenv.isDarwin 18)
        ];
        normal = {
          family = "Iosevka Medium";
        };
      };

      # Keybinding to send a newline
      keyboard = {
        bindings = [
          {
            key = "Return";
            mods = "Shift";
            chars = "\n";
          }
        ];
      };

      # Launch Zellij and attempt to attach to an existing session
      terminal.shell = {
        program = "${pkgs.zellij}/bin/zellij";
        args = [ "attach" "--create" "main" ];
      };
    };
  };
}