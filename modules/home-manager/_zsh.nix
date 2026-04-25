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

      # Shrink a PDF file
      function shrink_pdf() {
        if [ -z "''$1" ] || [ -z "''$2" ]; then
          echo "Usage: shrink_pdf <input.pdf> <output.pdf>"
          return 1
        fi
        local gs_path=$(whence -p gs)
        if [ -z "$gs_path" ]; then
          echo "Error: ghostscript (gs) not found in PATH"
          return 1
        fi
        "$gs_path" -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/screen -dNOPAUSE -dQUIET -dBATCH -sOutputFile="''$2" "''$1"
      }

      # Wi-Fi focus: `focus` prompts; `focus left` time left; `focus-off` lock now (see modules/macos/internet-focus.nix)
      if [[ $(uname -s) == Darwin ]]; then
        function focus() {
          if [[ $# -eq 1 ]] && [[ $1 == left ]]; then
            local statedir="''${XDG_STATE_HOME:-$HOME/.local/state}/shaikhlab/internet-focus"
            if [[ ! -f "$statedir/timer.until" ]]; then
              print -r "No focus internet timer is active."
              return 1
            fi
            local end_ts now left m s
            end_ts="$(<"$statedir/timer.until")"
            now=$(date +%s)
            left=$(( end_ts - now ))
            if [[ "$left" -le 0 ]]; then
              print -r "Timer has expired (stale state cleared)."
              rm -f "$statedir/timer.pid" "$statedir/timer.until"
              return 1
            fi
            m=$(( left / 60 ))
            s=$(( left % 60 ))
            printf '%s\n' "About $m min $s s left before focus lock."
            return 0
          fi
          if [[ $# -gt 0 ]]; then
            command focus "$@"
            return $?
          fi
          if ! whence -p focus &> /dev/null; then
            print -r "focus: focus(1) not in PATH (darwin rebuild?)" >&2
            return 1
          fi
          local statedir="''${XDG_STATE_HOME:-$HOME/.local/state}/shaikhlab/internet-focus"
          local log="$statedir/access.log"
          if [[ -s "$log" ]]; then
            print -r ""
            print -r "Last 5 reasons (access.log):"
            tail -n 5 "$log"
            print -r ""
          fi
          local reason minutes defm=''${INET_FOCUS_MINUTES:-45}
          read "reason?Why do you need the internet? "
          if [[ -z "$reason" ]]; then
            print -r "Aborted." >&2
            return 1
          fi
          print -nr "How many minutes (default $defm)? "
          read minutes
          [[ -z "$minutes" ]] && minutes="$defm"
          if [[ ! "$minutes" =~ '^[0-9]+$' ]] || [[ "$minutes" -lt 1 ]]; then
            print -r "focus: minutes must be a positive integer" >&2
            return 1
          fi
          mkdir -p "$statedir"
          print -r "$(date -Iseconds) ''${minutes}m — $reason" >> "$log"
          if [[ -f "$statedir/timer.pid" ]]; then
            kill "$(<"$statedir/timer.pid")" 2>/dev/null || true
            rm -f "$statedir/timer.pid" "$statedir/timer.until"
          fi
          if ! command focus unlock; then
            return 1
          fi
          print -r "Internet on for ''${minutes} minutes (then focus lock)."
          (
            sleep $((minutes * 60))
            command focus lock
            rm -f "$statedir/timer.pid" "$statedir/timer.until"
          ) &
          print -r $! > "$statedir/timer.pid"
          print -r $(( $(date +%s) + minutes * 60 )) > "$statedir/timer.until"
        }

        function focus-off() {
          if ! whence -p focus &> /dev/null; then
            print -r "focus-off: focus(1) not in PATH" >&2
            return 1
          fi
          local statedir="''${XDG_STATE_HOME:-$HOME/.local/state}/shaikhlab/internet-focus"
          if [[ -f "$statedir/timer.pid" ]]; then
            kill "$(<"$statedir/timer.pid")" 2>/dev/null || true
            rm -f "$statedir/timer.pid" "$statedir/timer.until"
          fi
          command focus lock
        }
      fi
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
