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
      journal = "jrnl --file /Users/adnan/JD/30-39_Documents/35_jrnl/journal.txt";
    };
    # inspo: https://discourse.nixos.org/t/brew-not-on-path-on-m1-mac/26770/4
    initContent = ''
      export SOPS_AGE_KEY_CMD='sudo ssh-to-age -private-key -i /nix/secret/initrd/ssh_host_ed25519_key'

      if [[ $(uname -m) == 'arm64' ]] && [[ $(uname -s) == 'Darwin' ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      fi

      if [ -z "$SSH_AUTH_SOCK" ]; then
        eval "$(ssh-agent -s)" &> /dev/null
        ssh-add ~/.ssh/id_ed25519 &> /dev/null
      fi

      # Convert any format to mp4
      function convert_to_mp4() {
        for file in *; do ffmpeg -i "''$file" -c:v libx264 -crf 23 -c:a aac -map_metadata 0 "''${file}_output.mp4"; done
      }

      # Convert any format to mp4 without reencoding
      function convert_to_mp4_without_reencoding() {
        for file in *; do ffmpeg -i "''$file" -c copy "''${file}_output.mp4"; done
      }

      # Download an mp3 from a YouTube link
      function download_mp3() {
        yt-dlp -x --audio-format mp3 "''$1"
      }

      # Download an mp4 from a YouTube link
      function download_mp4() {
        yt-dlp -f 'bv[height=1080][ext=mp4]+ba[ext=m4a]' --merge-output-format mp4 "''$1"
      }

      # Extract data from a QR code image
      function qr_decode() {
        if [ -z "''$1" ]; then
          echo "Usage: qr_decode <image>"
          return 1
        fi
        zbarimg -q --raw "''$1"
      }

      # Compress a PDF (ebook quality: decent size/quality balance)
      function compress_pdf() {
        if [ -z "''$1" ] || [ -z "''$2" ]; then
          echo "Usage: compress_pdf <input.pdf> <output.pdf>"
          return 1
        fi
        gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/ebook -dNOPAUSE -dQUIET -dBATCH -sOutputFile="''$2" "''$1"
      }

      # Compress an image (quality 75, strips metadata)
      function compress_img() {
        if [ -z "''$1" ] || [ -z "''$2" ]; then
          echo "Usage: compress_img <input> <output>"
          return 1
        fi
        convert "''$1" -quality 75 -strip "''$2"
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
