{
  config,
  pkgs,
  vars,
  ...
}: let
  hostname = config.networking.hostName;
  email = vars.userEmail;

  # Invoked by mdadm's mdmonitor unit on RAID events (Fail, FailSpare,
  # SpareActive, DegradedArray, RebuildStarted, RebuildFinished, etc.).
  # mdadm passes: $1 = event, $2 = md device, $3 = component device.
  mdadmNotify = pkgs.writeShellScriptBin "mdadm-notify" ''
    set -u
    EVENT="''${1:-unknown}"
    ARRAY="''${2:-unknown}"
    COMPONENT="''${3:-}"
    {
      echo "To: ${email}"
      echo "From: ${email}"
      echo "Subject: [${hostname}] mdadm: $EVENT on $ARRAY"
      echo "MIME-Version: 1.0"
      echo "Content-Type: text/plain; charset=utf-8"
      echo
      echo "================================================================"
      echo "RAID EVENT — ${hostname} — $(date '+%Y-%m-%d %H:%M:%S %Z')"
      echo "================================================================"
      echo
      echo "Event:     $EVENT"
      echo "Array:     $ARRAY"
      echo "Component: $COMPONENT"
      echo
      echo "--- /proc/mdstat ---"
      cat /proc/mdstat 2>&1 || true
      echo
      echo "--- mdadm --detail $ARRAY ---"
      ${pkgs.mdadm}/bin/mdadm --detail "$ARRAY" 2>&1 || true
    } | /run/wrappers/bin/sendmail -t
  '';

  # Monthly SMART + mdadm health digest. Buffers everything to a tempdir so we
  # can derive a verdict (subject + table status column + action block) before
  # composing the email.
  healthReport = pkgs.writeShellScriptBin "drive-health-report" ''
    set -u

    MDADM=${pkgs.mdadm}/bin/mdadm
    SMARTCTL=${pkgs.smartmontools}/bin/smartctl
    LSBLK=${pkgs.util-linux}/bin/lsblk
    AWK=${pkgs.gawk}/bin/awk

    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT

    # Filter out kernel-virtual block devices that lsblk reports as "disk"
    # but that aren't real, SMART-capable hardware:
    #   zram*  in-RAM compressed swap (zramSwap.enable in modules/nixos/base.nix)
    #   loop*  loopback-mounted images
    #   sr*    optical drives (mostly absent on a server)
    #   md*    md raid arrays (we already iterate $MD_DEVS separately)
    DISKS=$($LSBLK -dn -o NAME,TYPE \
      | $AWK '$2=="disk" && $1 !~ /^(zram|loop|sr|md)/ {print "/dev/"$1}')

    MD_DEVS=""
    for md in /dev/md[0-9]*; do
      [ -b "$md" ] && MD_DEVS="$MD_DEVS $md"
    done

    # Build a map of "<member-basename> <md><[slot]>" so we can stamp each
    # disk with its array role in the table.
    : > "$TMP/role-map"
    for md in $MD_DEVS; do
      mdname=$(basename "$md")
      $MDADM --detail "$md" 2>/dev/null | $AWK -v mdname="$mdname" '
        /^[[:space:]]+[0-9-]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9-]+[[:space:]]+/ \
          && $NF ~ /^\/dev\// {
          slot = $4; dev = $NF
          sub("^/dev/", "", dev)
          if (slot == "-") slot = "spare"
          printf "%s %s[%s]\n", dev, mdname, slot
        }' >> "$TMP/role-map"
    done

    role_for() {
      base=$(basename "$1")
      r=$($AWK -v d="$base" '$1==d{print $2; exit}' "$TMP/role-map")
      if [ -n "$r" ]; then echo "$r"
      # Read /proc/mounts directly so we don't depend on `mount` being on
      # PATH for the systemd unit. Match either the bare disk or any of its
      # partitions (nvme0n1 -> nvme0n1p1, sda -> sda1) mounted at /boot or /nix.
      elif grep -qE "^$1[p0-9]*[[:space:]]+/(boot|nix)[[:space:]]" /proc/mounts; then
        echo "boot"
      else
        echo "-"
      fi
    }

    # `smartctl -x` ATA attribute table layout:
    #   $1=ID# $2=NAME $3=FLAGS $4=VALUE $5=WORST $6=THRESH $7=FAIL $8=RAW_VALUE
    # ($8 is the first whitespace token of RAW; e.g. for
    #  "Temperature_Celsius ... 31 (Min/Max 16/106)" we get "31".)
    sata_raw() { # $1=file $2=name -> raw or "-"
      v=$($AWK -v n="$2" '$2==n{print $8; f=1; exit} END{if(!f) print ""}' "$1")
      [ -n "$v" ] && echo "$v" || echo "-"
    }
    # Normalized VALUE column (0-100, higher=better).
    sata_val() {
      $AWK -v n="$2" '$2==n{print $4; exit}' "$1"
    }
    nvme_field() { # $1=file $2=label-prefix
      $AWK -F: -v lbl="$2" '
        index($0, lbl) == 1 {
          sub("^[^:]*:[[:space:]]*", "")
          gsub(",", "")
          gsub(/[[:space:]]+$/, "")
          print
          exit
        }' "$1"
    }

    # ----- collect per-disk data -----
    : > "$TMP/rows"
    : > "$TMP/replace-list"
    PROBLEMS=""
    WATCHES=""

    for DEV in $DISKS; do
      base=$(basename "$DEV")
      smart_file="$TMP/smart.$base"
      $SMARTCTL -x "$DEV" > "$smart_file" 2>&1 || true

      health=$($AWK -F: '
        /SMART overall-health/ {
          sub("^[^:]*:[[:space:]]*", "")
          gsub(/[[:space:]]+$/, "")
          print; exit
        }' "$smart_file")
      [ -z "$health" ] && health="UNKNOWN"

      role=$(role_for "$DEV")

      status="OK"

      case "$DEV" in
        /dev/nvme*)
          pwr=$(nvme_field "$smart_file" "Power On Hours" | tr -d ' ')
          temp=$(nvme_field "$smart_file" "Temperature" | $AWK '{print $1}')
          used=$(nvme_field "$smart_file" "Percentage Used" | tr -d ' %')
          critwarn=$(nvme_field "$smart_file" "Critical Warning" | tr -d ' ')
          integrity=$(nvme_field "$smart_file" "Media and Data Integrity Errors" | tr -d ' ')
          : "''${pwr:=0}" "''${temp:=0}" "''${used:=0}" "''${critwarn:=0x00}" "''${integrity:=0}"

          realloc="-"; pending="-"; uncorr="$integrity"

          if [ "$health" != "PASSED" ] || [ "$critwarn" != "0x00" ] || [ "$integrity" != "0" ]; then
            status="REPLACE"
          elif [ "$used" -gt 80 ] 2>/dev/null; then
            status="REPLACE"
          elif [ "$used" -gt 50 ] 2>/dev/null || [ "$temp" -gt 55 ] 2>/dev/null; then
            status="WATCH"
          fi
          ;;
        *)
          pwr=$(sata_raw "$smart_file" "Power_On_Hours")
          # A few drives append units to the raw value ("4198h+15m"); keep
          # only the leading integer so the table column stays clean.
          case "$pwr" in ""|-) ;; *) pwr=$(printf '%s' "$pwr" | grep -oE '^[0-9]+') ;; esac
          [ -z "$pwr" ] && pwr="-"
          temp=$(sata_raw "$smart_file" "Temperature_Celsius")
          [ "$temp" = "-" ] && temp=$(sata_raw "$smart_file" "Airflow_Temperature_Cel")
          realloc=$(sata_raw "$smart_file" "Reallocated_Sector_Ct")
          [ "$realloc" = "-" ] && realloc=$(sata_raw "$smart_file" "Reallocate_NAND_Blk_Cnt")
          [ "$realloc" = "-" ] && realloc=$(sata_raw "$smart_file" "Reallocated_Event_Count")
          pending=$(sata_raw "$smart_file" "Current_Pending_Sector")
          uncorr=$(sata_raw "$smart_file" "Offline_Uncorrectable")
          [ "$uncorr" = "-" ] && uncorr=$(sata_raw "$smart_file" "Reported_Uncorrect")

          # Wear indicator: vendor names first, then the universal
          # Available_Reservd_Space (id 232) whose value column counts down
          # from 100 — this is what works for SSDs not in smartctl's
          # database (e.g. WD Blue SA510). value=100 means brand new.
          wear_val=""
          for attr in Wear_Leveling_Count Remaining_Lifetime_Perc \
                      Percent_Lifetime_Remain SSD_Life_Left \
                      Available_Reservd_Space; do
            v=$(sata_val "$smart_file" "$attr")
            if [ -n "$v" ]; then wear_val=$v; break; fi
          done
          if [ -n "$wear_val" ]; then used=$((100 - wear_val)); else used="-"; fi

          if [ "$health" != "PASSED" ]; then status="REPLACE"; fi
          for v in "$realloc" "$pending" "$uncorr"; do
            case "$v" in
              ""|-|0) ;;
              *) status="REPLACE" ;;
            esac
          done
          if [ "$status" = "OK" ] && [ "$used" != "-" ]; then
            if [ "$used" -gt 80 ]; then status="REPLACE"
            elif [ "$used" -gt 50 ]; then status="WATCH"
            fi
          fi
          if [ "$status" = "OK" ] && [ "$temp" != "-" ] && [ "$temp" -gt 55 ] 2>/dev/null; then
            status="WATCH"
          fi
          ;;
      esac

      case "$status" in
        REPLACE)
          PROBLEMS="$PROBLEMS $DEV"
          model=$($AWK -F: '
            /^(Device Model|Model Number)/ {
              sub("^[^:]*:[[:space:]]*", ""); print; exit
            }' "$smart_file")
          serial=$($AWK -F: '
            /^Serial Number/ {
              sub("^[^:]*:[[:space:]]*", ""); print; exit
            }' "$smart_file")
          printf '%s|%s|%s|%s\n' "$DEV" "$role" "$model" "$serial" >> "$TMP/replace-list"
          ;;
        WATCH)
          WATCHES="$WATCHES $DEV"
          ;;
      esac

      [ "$used" = "-" ] && used_disp="-" || used_disp="$used %"
      [ "$pwr"  = "-" ] && pwr_disp="-"  || pwr_disp="$pwr h"
      [ "$temp" = "-" ] && temp_disp="-" || temp_disp="$temp C"

      printf '%-13s  %-9s  %-8s  %-7s  %6s  %8s  %5s  %7s  %7s  %7s\n' \
        "$DEV" "$role" "$status" "$health" \
        "$used_disp" "$pwr_disp" "$temp_disp" \
        "$realloc" "$pending" "$uncorr" >> "$TMP/rows"
    done

    # ----- verdict + subject -----
    n_drives=$(wc -l < "$TMP/rows" | tr -d ' ')
    if [ -n "$PROBLEMS" ]; then
      VERDICT="REPLACE$PROBLEMS"
      SUBJECT="[${hostname}] drive health: REPLACE$PROBLEMS"
    elif [ -n "$WATCHES" ]; then
      VERDICT="WATCH$WATCHES (no immediate action; trend rising)"
      SUBJECT="[${hostname}] drive health: WATCH$WATCHES"
    else
      VERDICT="ALL OK ($n_drives drives, RAID clean)"
      SUBJECT="[${hostname}] drive health: ALL OK ($n_drives drives, RAID clean)"
    fi

    # ----- compose email -----
    {
      echo "To: ${email}"
      echo "From: ${email}"
      echo "Subject: $SUBJECT"
      echo "MIME-Version: 1.0"
      echo "Content-Type: text/plain; charset=utf-8"
      echo
      echo "================================================================"
      echo "SUMMARY — ${hostname} — $(date '+%Y-%m-%d %H:%M %Z')"
      echo "================================================================"
      echo
      echo "Verdict:  $VERDICT"
      echo
      echo "RAID:"
      for md in $MD_DEVS; do
        detail=$($MDADM --detail "$md" 2>/dev/null)
        state=$(printf '%s\n' "$detail" | $AWK -F: '
          /^[[:space:]]*State[[:space:]]*:/ {
            sub("^[^:]*:[[:space:]]*", ""); gsub(/[[:space:]]+$/, ""); print; exit
          }')
        raid_devs=$(printf '%s\n' "$detail" | $AWK -F: '
          /Raid Devices/ { sub("^[^:]*:[[:space:]]*",""); print; exit }')
        active=$(printf '%s\n' "$detail" | $AWK -F: '
          /Active Devices/ { sub("^[^:]*:[[:space:]]*",""); print; exit }')
        failed=$(printf '%s\n' "$detail" | $AWK -F: '
          /Failed Devices/ { sub("^[^:]*:[[:space:]]*",""); print; exit }')
        spare=$(printf '%s\n' "$detail" | $AWK -F: '
          /Spare Devices/ { sub("^[^:]*:[[:space:]]*",""); print; exit }')
        uu=$(grep -A1 "^$(basename "$md") :" /proc/mdstat | grep -oE '\[[U_]+\]' | head -1)
        printf '  %s  %s  %s  %s/%s active   %s failed   %s spare\n' \
          "$md" "$state" "$uu" "$active" "$raid_devs" "$failed" "$spare"
      done
      echo
      printf '%-13s  %-9s  %-8s  %-7s  %6s  %8s  %5s  %7s  %7s  %7s\n' \
        "DEVICE" "ROLE" "STATUS" "HEALTH" "USED" "PWR_ON" "TEMP" "REALLOC" "PENDING" "UNCORR"
      cat "$TMP/rows"
      echo
      if [ -s "$TMP/replace-list" ]; then
        echo "Action — replace the following drive(s):"
        echo
        while IFS='|' read -r d r m s; do
          echo "  $d  ($m, S/N $s)"
          case "$r" in
            md*)
              md_target="/dev/''${r%%\[*}"
              echo "      sudo mdadm --manage $md_target --fail   $d"
              echo "      sudo mdadm --manage $md_target --remove $d"
              echo "      # physically swap the disk in the same bay"
              echo "      sudo mdadm --manage $md_target --add    $d"
              echo "      # then watch:  cat /proc/mdstat"
              ;;
            boot)
              echo "      (boot drive — restore from backup, then reinstall NixOS)"
              ;;
            *)
              echo "      (not a RAID member — investigate manually)"
              ;;
          esac
          echo
        done < "$TMP/replace-list"
      fi
      echo "Legend:"
      echo "  USED       SSD wear consumed (NVMe Percentage_Used,"
      echo "             or 100 - SATA Wear_Leveling_Count value)"
      echo "  OK         every threshold green"
      echo "  WATCH      wear > 50%, or temperature > 55 C"
      echo "  REPLACE    SMART FAILED, or Reallocated/Pending/Uncorrectable > 0,"
      echo "             or NVMe Critical_Warning != 0x00, or wear > 80%"
      echo
      echo "================================================================"
      echo "APPENDIX — full diagnostic output"
      echo "================================================================"
      echo
      echo "--- /proc/mdstat ---"
      cat /proc/mdstat 2>&1 || true
      echo
      echo "--- mdadm --detail --scan --verbose ---"
      $MDADM --detail --scan --verbose 2>&1 || true
      echo
      for md in $MD_DEVS; do
        echo "--- mdadm --detail $md ---"
        $MDADM --detail "$md" 2>&1 || true
        echo
      done
      for DEV in $DISKS; do
        echo "--- smartctl -x $DEV ---"
        cat "$TMP/smart.$(basename "$DEV")" 2>&1 || true
        echo
      done
    } | /run/wrappers/bin/sendmail -t
  '';
in {
  imports = [
    ./mail.nix
  ];

  environment.systemPackages = [
    pkgs.smartmontools
    mdadmNotify
    healthReport
  ];

  # SMART monitoring.
  #   -a              : monitor all standard attributes + self-test log + errors
  #   -o on           : enable automatic offline testing
  #   -S on           : enable attribute autosave
  #   -n standby,q    : don't spin up a drive in standby (no-op for SSDs; future-proof)
  #   -s (...)        : schedule short self-test nightly at 02:00,
  #                     long self-test at 03:00 every Saturday
  # Self-test schedule syntax: see smartd.conf(5).
  services.smartd = {
    enable = true;
    autodetect = true;
    defaults.monitored = "-a -o on -S on -n standby,q -s (S/../.././02|L/../../6/03)";
    notifications = {
      mail = {
        enable = true;
        sender = vars.userEmail;
        recipient = vars.userEmail;
        mailer = "/run/wrappers/bin/sendmail";
      };
      test = false;
    };
  };

  # Monthly health digest. `OnCalendar = "monthly"` fires at 00:00 on the 1st;
  # randomized delay spreads load if more servers are added later.
  systemd.services.drive-health-report = {
    description = "Monthly drive health email report";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${healthReport}/bin/drive-health-report";
    };
  };
  systemd.timers.drive-health-report = {
    description = "Monthly drive health email report";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "monthly";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
}
