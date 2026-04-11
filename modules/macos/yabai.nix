{...}: {
  services.yabai = {
    enable = true;
    enableScriptingAddition = true;
    config = {
      layout = "bsp";
      top_padding = 10;
      bottom_padding = 10;
      left_padding = 10;
      right_padding = 400; # Reserves the empty space on the right
      window_gap = 10;
    };
    extraConfig = ''
      # Tell Yabai to completely ignore Reminders and keep it visible on all workspaces
      yabai -m rule --add app='^Reminders$' manage=off sticky=on
    '';
  };
}