{...}: {
  # LinearMouse reads ~/.config/linearmouse/linearmouse.json (and hot-reloads).
  # https://github.com/linearmouse/linearmouse/blob/main/Documentation/Configuration.md
  # Captures the current SteelSeries Rival 3 setup. The GUI cannot save over
  # this store symlink; change the attrset here instead.
  home.file.".config/linearmouse/linearmouse.json" = {
    text = builtins.toJSON {
      "$schema" = "https://schema.linearmouse.app/0.7.6";
      schemes = [
        {
          "if" = {
            device = {
              category = "mouse";
              productName = "SteelSeries Rival 3";
              productID = "0x184c";
              vendorID = "0x1038";
            };
          };
          pointer = {
            acceleration = 0;
            speed = 0.4;
            disableAcceleration = false;
          };
          scrolling.reverse.vertical = true;
        }
      ];
    };
  };
}
