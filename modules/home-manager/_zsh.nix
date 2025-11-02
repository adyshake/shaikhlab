{pkgs, ...}: {
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases = {
      ".." = "cd ..";
      cat = "bat --style=plain --theme=base16 --paging=never ";
      neofetch = "fastfetch";
      gs = "git status";
      gl = "git log";
      gp = "git pull";
      gd = "git diff";
      gca = "git commit --amend";
      glo = "git fetch && git log HEAD..origin";
    };
    # inspo: https://discourse.nixos.org/t/brew-not-on-path-on-m1-mac/26770/4
    initContent = ''
      fortune

      if [[ $(uname -m) == 'arm64' ]] && [[ $(uname -s) == 'Darwin' ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      fi

      if [ -z "$SSH_AUTH_SOCK" ]; then
        eval "$(ssh-agent -s)" &> /dev/null
        ssh-add ~/.ssh/id_ed25519 &> /dev/null
      fi

      # Convert any format to mp4
      function convert_to_mp4() {
        for file in *; do ffmpeg -i "$file" -c:v libx264 -crf 23 -c:a aac -map_metadata 0 "${file}_output.mp4"; done
      }

      # Convert any format to mp4 without reencoding
      function convert_to_mp4_without_reencoding() {
        for file in *; do ffmpeg -i "$file" -c copy "${file}_output.mp4"; done
      }

      # Download an mp3 from a YouTube link
      function download_mp3() {
        yt-dlp -x --audio-format mp3 --prefer-ffmpeg "$1"
      }

      # Download an mp4 from a YouTube link
      function download_mp4() {
        yt-dlp -f 'bv[height=1080][ext=mp4]+ba[ext=m4a]' --merge-output-format mp4 "$1"
      }
    '';
    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
      # inspo: https://discourse.nixos.org/t/zsh-zplug-powerlevel10k-zshrc-is-readonly/30333/3
      {
        name = "powerlevel10k-config";
        src = ./_p10k;
        file = "p10k.zsh";
      }
    ];
  };
}
