{pkgs, ...}: {
  home = {
    packages = with pkgs; [
      inter
      iosevka
      # Icons-only Nerd Font. iTerm2 uses Monaco for text and falls back to this
      # for the glyphs terminal tools (lsd, omz themes) emit, so folder icons
      # render without changing the text font.
      nerd-fonts.symbols-only
    ];
  };
}
