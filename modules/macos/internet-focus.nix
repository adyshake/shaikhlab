{
  lib,
  pkgs,
  vars,
  ...
}: let
  ns = "/usr/sbin/networksetup";

  focus-wifi = pkgs.writeShellApplication {
    name = "focus";
    text = ''
      set -euo pipefail

      wifi_device() {
        ${ns} -listallhardwareports | /usr/bin/awk '
          BEGIN { RS = "" }
          /Wi-Fi|WLAN|AirPort/ {
            for (i = 1; i <= NF; i++)
              if ($i == "Device:") {
                print $(i + 1)
                exit
              }
          }
        '
      }

      lock() {
        local dev
        dev="$(wifi_device || true)"
        if [[ -z "$dev" ]]; then
          echo >&2 "focus: no Wi-Fi interface found; nothing to disable."
          return 0
        fi
        if ! ${ns} -setairportpower "$dev" off 2>/dev/null; then
          echo >&2 "focus: Wi-Fi off failed (try: sudo ${ns} -setairportpower $dev off)"
          return 1
        fi
      }

      unlock() {
        local dev
        dev="$(wifi_device || true)"
        if [[ -z "$dev" ]]; then
          echo >&2 "focus: no Wi-Fi interface found."
          return 1
        fi
        if ! ${ns} -setairportpower "$dev" on 2>/dev/null; then
          echo >&2 "focus: Wi-Fi on failed (try: sudo ${ns} -setairportpower $dev on)"
          return 1
        fi
      }

      case "''${1:-}" in
        lock) lock ;;
        unlock) unlock ;;
        *)
          echo "usage: focus {lock|unlock}" >&2
          exit 2
          ;;
      esac
    '';
  };

  wakeHook = pkgs.writeShellScript "shaikhlab-focus-wake" ''
    exec ${lib.getExe focus-wifi} lock
  '';
in {
  environment.systemPackages = [focus-wifi];

  launchd.user.agents = {
    shaikhlab-sleepwatcher = {
      path = [pkgs.sleepwatcher];
      command = "${lib.getExe pkgs.sleepwatcher} -V -w ${wakeHook}";
      serviceConfig = {
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "/Users/${vars.userName}/Library/Logs/shaikhlab-sleepwatcher.log";
        StandardErrorPath = "/Users/${vars.userName}/Library/Logs/shaikhlab-sleepwatcher.log";
      };
    };

    shaikhlab-focus-login = {
      command = "${lib.getExe focus-wifi} lock";
      serviceConfig = {
        RunAtLoad = true;
      };
    };
  };
}
