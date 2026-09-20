{
  config,
  pkgs,
  vars,
  lib,
  ...
}: let
  absAudiobooks = "${config.nixarr.mediaDir}/library/audiobooks";
  absPodcasts = "${config.nixarr.mediaDir}/library/podcasts";

  # Tag a torrent `audiobook` or `podcast` in Transmission. On completion
  # (and every minute for torrents tagged after they finished) this
  # hardlinks the files into the matching Audiobookshelf library.
  transmissionToAbs = pkgs.writeShellApplication {
    name = "transmission-to-abs";
    runtimeInputs = [pkgs.curl pkgs.jq pkgs.coreutils pkgs.gawk pkgs.gnugrep];
    text = ''
      export ABS_AUDIOBOOKS=${lib.escapeShellArg absAudiobooks}
      export ABS_PODCASTS=${lib.escapeShellArg absPodcasts}
      export TRANSMISSION_USER=${lib.escapeShellArg vars.userName}
      export TRANSMISSION_RPC_URL="http://127.0.0.1:9091/transmission/rpc"
      ${pkgs.bash}/bin/bash ${./nixarr/transmission-to-abs.sh}
    '';
  };
in {
  imports = [
    ./_acme.nix
    ./_nginx.nix
    ./_cloudflared.nix
  ];

  sops = {
    secrets = {
      #"kopia-repository-token" = {};
      "wg.conf" = {
        format = "binary";
        sopsFile = ./../secrets/wg.conf;
      };
      "transmission-rpc-credentials" = {
        format = "binary";
        sopsFile = ./../secrets/transmission-rpc-credentials;
        mode = "0400";
        restartUnits = ["transmission.service" "arr-bootstrap.service"];
      };
    };
  };

  vpnNamespaces.wg.accessibleFrom = lib.mkForce [
    "192.168.0.0/16"
    "100.64.0.0/10"
    "127.0.0.1"
  ];

  nixarr = {
    enable = true;
    mediaDir = "/data/fun";
    stateDir = "/var/lib/nixarr";

    # Jellyfin 12.0 (from 10.11.11): wait for nixpkgs (server + web + ffmpeg
    # 8.1 + .NET 10). Before first 12.0 start: stop jellyfin, copy
    # /var/lib/nixarr/jellyfin (DB rewrite is not rollback-able from a
    # generation), drop third-party plugins, update Infuse/InfuseSync
    # (>=1.5.3). After: full library scan, then reinstall official plugins.
    # Add proxyWebsockets on watch.adnanshaikh.com when shipping. Pin the
    # package so autoUpgrade cannot migrate the DB on a lock bump.
    jellyfin.enable = true;
    # Player (host network, like Jellyfin / Navidrome). First visit
    # listen.adnanshaikh.com, create the admin user, add a library
    # pointing at /data/fun/library/audiobooks. Tag Transmission
    # torrents `audiobook` (or `podcast`) to hardlink them in.
    audiobookshelf.enable = true;
    prowlarr = {
      enable = true;
      vpn.enable = true;
    };
    radarr = {
      enable = true;
      vpn.enable = true;
    };
    sonarr = {
      enable = true;
      vpn.enable = true;
    };
    lidarr = {
      enable = true;
      vpn.enable = true;
    };

    recyclarr = {
      enable = true;
      configuration = let
        # Size limits are MB/min. 1080p WEB/Bluray stay at TRaSH defaults
        # (unlimited) so normal encodes are not rejected. 4K is capped
        # (~50GB for a 2.5h movie) so a fallback 4K is not an 80GB remux.
        cap = max: preferred: {inherit max preferred;};
        sonarrSizeCaps = [
          ({name = "Bluray-1080p Remux";} // cap 200 160)
          ({name = "WEBRip-2160p";} // cap 220 160)
          ({name = "WEBDL-2160p";} // cap 220 160)
          ({name = "Bluray-2160p";} // cap 280 200)
          ({name = "Bluray-2160p Remux";} // cap 280 200)
        ];
        radarrSizeCaps = [
          ({name = "WEBRip-2160p";} // cap 280 180)
          ({name = "WEBDL-2160p";} // cap 280 180)
          ({name = "Bluray-2160p";} // cap 350 220)
          ({name = "Remux-2160p";} // cap 350 220)
        ];

        # Same-resolution sources are grouped so quality does not trump
        # a well-seeded WEB-DL. Radarr then ranks by CF score (original
        # language preferred, not English dubs) and seeders. Remux is
        # omitted — that is the 80GB path.
        resolutionLadder = [
          {
            name = "1080p";
            qualities = ["Bluray-1080p" "WEBDL-1080p" "WEBRip-1080p"];
          }
          {
            name = "2160p";
            qualities = ["Bluray-2160p" "WEBDL-2160p" "WEBRip-2160p"];
          }
          {
            name = "720p";
            qualities = ["Bluray-720p" "WEBDL-720p" "WEBRip-720p"];
          }
          {name = "HDTV-1080p";}
          {name = "HDTV-720p";}
        ];
        movieLadder = name: {
          inherit name;
          reset_unmatched_scores.enabled = true;
          # Language: Not Original is -100. Must be below 0 so a
          # dubbed release still downloads when no original exists.
          min_format_score = -200;
          upgrade = {
            allowed = true;
            until_quality = "1080p";
            until_score = 10000;
          };
          qualities = resolutionLadder;
        };
        # Prefer the title's original audio (JA/FR/KO/…) over an English
        # dub, without blocking the dub if original is unavailable.
        preferOriginal = name: trashId: {
          trash_ids = [trashId];
          assign_scores_to = [
            {
              inherit name;
              score = -100;
            }
          ];
        };
        radarrNotOriginal = "d6e9318c875905d6cfb5bee961afcea9";
        sonarrNotOriginal = "ae575f95ab639ba5d15f663bf019e3e8";
        # Recyclarr v8 guide-backed profiles (include templates are gone).
        sonarrWeb1080p = "72dae194fc92bf828f32cde7744e51a1";
        sonarrAnime = "20e0fc959f1f1704bed501f23bdae76f";
        radarrHd = "d1d67249d3890e49bc12e275d989a7e9";
        radarrUhd = "64fb5f9858489bdac2af690e27c8f42f";
        radarrAnime = "722b624f9af1e492284c4bc842153a38";
      in {
        sonarr = {
          anime-sonarr-v4 = {
            base_url = "https://sonarr.adnanshaikh.com";
            api_key = "!env_var SONARR_API_KEY";

            delete_old_custom_formats = true;

            quality_definition = {
              type = "anime";
              qualities = sonarrSizeCaps;
            };

            quality_profiles = [
              {
                trash_id = sonarrAnime;
                name = "Remux-1080p - Anime";
                reset_unmatched_scores.enabled = true;
              }
            ];
          };

          web-1080p-v4 = {
            base_url = "https://sonarr.adnanshaikh.com";
            api_key = "!env_var SONARR_API_KEY";

            quality_definition = {
              type = "series";
              qualities = sonarrSizeCaps;
            };

            quality_profiles = [
              {
                trash_id = sonarrWeb1080p;
                name = "WEB-1080p";
                reset_unmatched_scores.enabled = true;
                min_format_score = -200;
              }
            ];

            custom_formats = [
              (preferOriginal "WEB-1080p" sonarrNotOriginal)
              {
                trash_ids = [
                  "85c61753df5da1fb2aab6f2a47426b09" # BR-DISK
                  "9c11cd3f07101cdba90a2d81cf0e56b4" # LQ
                ];
                assign_scores_to = [
                  {
                    name = "WEB-1080p";
                    score = -10000;
                  }
                ];
              }
              {
                trash_ids = [
                  "47435ece6b99a0b477caf360e79ba0bb"
                  "9b64dff695c2115facf1b6ea59c9bd07"
                ];
                assign_scores_to = [
                  {
                    name = "WEB-1080p";
                    score = 0;
                  }
                ];
              }
            ];
          };
        };
        radarr = {
          anime = {
            base_url = "https://radarr.adnanshaikh.com";
            api_key = "!env_var RADARR_API_KEY";

            quality_definition = {
              type = "anime";
            };

            quality_profiles = [
              {
                trash_id = radarrAnime;
                name = "Remux-1080p - Anime";
                reset_unmatched_scores.enabled = true;
              }
            ];

            custom_formats = [
              {
                trash_ids = [
                  "064af5f084a0a24458cc8ecd3220f93f" # Uncensored
                  "a5d148168c4506b55cf53984107c396e" # 10bit
                  "4a3b087eea2ce012fcc1ce319259a3be" # Dual Audio
                ];
                assign_scores_to = [
                  {
                    name = "Remux-1080p - Anime";
                    score = 0;
                  }
                ];
              }
            ];
          };

          # One Radarr instance so quality defs and CFs do not fight.
          # 1080p first, then size-capped 4K, then 720p. Existing
          # remux/HD profile names are kept so Recyclarr adopts them.
          movies = {
            base_url = "https://radarr.adnanshaikh.com";
            api_key = "!env_var RADARR_API_KEY";

            quality_definition = {
              type = "movie";
              qualities = radarrSizeCaps;
            };

            quality_profiles = [
              (movieLadder "HD Blueray + WEB" // {trash_id = radarrHd;})
              (movieLadder "1080p then 4K" // {trash_id = radarrUhd;})
              (movieLadder "Remux + WEB 1080p" // {trash_id = radarrUhd;})
              (movieLadder "UHD Bluray + WEB" // {trash_id = radarrUhd;})
            ];

            delete_old_custom_formats = true;

            custom_formats = [
              (preferOriginal "HD Blueray + WEB" radarrNotOriginal)
              (preferOriginal "1080p then 4K" radarrNotOriginal)
              (preferOriginal "Remux + WEB 1080p" radarrNotOriginal)
              (preferOriginal "UHD Bluray + WEB" radarrNotOriginal)
              {
                trash_ids = [
                  "dc98083864ea246d05a42df0d05f81cc" # x265 (HD)
                  "839bea857ed2c0a8e084f3cbdbd65ecb" # x265 (no HDR/DV)
                ];
                assign_scores_to = [
                  {
                    name = "HD Blueray + WEB";
                    score = 0;
                  }
                ];
              }
            ];
          };
        };
      };
    };

    transmission = {
      enable = true;
      package = pkgs.transmission_4;
      # todo: figure out how to update this easier
      peerPort = 46634;
      vpn.enable = true;
      extraAllowedIps = ["100.64.0.0/10"];
      credentialsFile = config.sops.secrets."transmission-rpc-credentials".path;
      extraSettings = {
        peer-limit-global = 500;
        cache-size-mb = 256;
        download-dir = "/data/transmission/downloads";
        incomplete-dir = "/data/transmission/.incomplete";
        incomplete-dir-enabled = true;
        download-queue-enabled = true;
        download-queue-size = 20;
        speed-limit-up = 500;
        speed-limit-up-enabled = true;
        rpc-bind-address = "0.0.0.0";
        rpc-authentication-required = false;
        rpc-username = vars.userName;
        rpc-whitelist-enabled = false;
        # nixarr defaults this on (threshold 10, global, no cooldown).
        # One burst of bad Basic auth — browser saved password or *arr —
        # 403s every RPC client until transmission.service restarts.
        anti-brute-force-enabled = false;
        ratio-limit = 1.0;
        ratio-limit-enabled = true;
        # Overrides nixarr's cross-seed hook (disabled here). Instant
        # import when a tagged torrent finishes; the timer covers tags
        # applied after completion.
        script-torrent-done-enabled = true;
        script-torrent-done-filename = lib.getExe transmissionToAbs;
      };
    };

    vpn = {
      enable = true;
      wgConf = config.sops.secrets."wg.conf".path;
    };
  };

  services.flaresolverr.enable = true;

  # Lidarr (VPN-bound, above) is the indexer/downloader. Navidrome only
  # scans `${mediaDir}/library/music` and streams it over Subsonic to
  # Amperfy. Host network, same as Jellyfin — no indexer traffic here.
  services.navidrome = {
    enable = true;
    settings = {
      MusicFolder = "/data/fun/library/music";
      Address = "127.0.0.1";
      Port = 4533;
      EnableInsightsCollector = false;
      # Amperfy "server chooses codec" omits `format` and only sends a
      # bitrate cap. Without this, Navidrome downsamples to opus (its
      # default), which iOS often can't play. Bitrate itself is not a
      # navidrome.json key — it lives per-player in the UI (Settings →
      # Players → Max. Bit Rate).
      DefaultDownsamplingFormat = "mp3";
      # `/download` follows the player's transcoding profile instead of
      # shipping the original FLAC. Stream still uses the same mp3
      # profile when the client asks for mp3 (Amperfy cache default).
      AutoTranscodeDownload = true;
      Scanner = {
        Schedule = "@every 1h";
        ScanOnStartup = true;
      };
    };
  };

  # All systemd service overrides for the nixarr stack live in this single
  # attrset so the `vpnBound` helper can be reused without conflicting with
  # other `systemd.services.*` definitions in the same module.
  #
  # 1) wg.service: actively probe blocky before wg-up runs (fixes cold-boot
  #    DNS race where wg-up's 5-attempt retry loses to blocky still warming).
  #    If the probe times out we still `exit 0` so systemd's Restart=on-failure
  #    can take over -- this can never block boot forever.
  # 2) vpnBound units (radarr/sonarr/prowlarr/lidarr/transmission/flaresolverr):
  #    hard-coupled to wg.service via BindsTo+After. They refuse to start if
  #    wg is down, are force-stopped if wg dies, and retry themselves once
  #    wg recovers. mkDefault on Restart lets nixarr's own tuning (if any) win.
  # 3) navidrome / audiobookshelf are NOT vpnBound (host network, like
  #    Jellyfin). PrivateUsers is forced off so the media group survives.
  systemd.services = let
    vpnBound = extra:
      lib.recursiveUpdate {
        bindsTo = ["wg.service"];
        after = ["wg.service"];
        # Auto-start us whenever wg.service starts. BindsTo gives stop-on-stop,
        # but without a symmetric wantedBy, a clean stop (triggered by wg
        # going down) never gets reversed when wg comes back up. Adding
        # wg.service as a wantedBy target installs `Wants=<us>` on wg, so
        # every start of wg pulls us along.
        wantedBy = ["wg.service"];
        serviceConfig = {
          Restart = lib.mkDefault "on-failure";
          RestartSec = lib.mkDefault "15s";
        };
      }
      extra;
  in {
    wg = {
      after = [
        "network-online.target"
        "blocky.service"
        "nss-lookup.target"
      ];
      wants = [
        "network-online.target"
        "blocky.service"
        "nss-lookup.target"
      ];
      preStart = ''
        endpoint=$(${pkgs.gnused}/bin/sed -n \
          's/^[[:space:]]*Endpoint[[:space:]]*=[[:space:]]*\([^:]*\):.*/\1/p' \
          ${config.sops.secrets."wg.conf".path} | head -n1)
        if [ -z "$endpoint" ]; then
          echo "wg preStart: could not extract endpoint from wg.conf, skipping probe" >&2
          exit 0
        fi
        echo "wg preStart: waiting for blocky to resolve $endpoint..." >&2
        for i in $(seq 1 60); do
          if ${pkgs.dnsutils}/bin/dig +short +time=2 +tries=1 "$endpoint" @127.0.0.1 \
               | ${pkgs.gnugrep}/bin/grep -qE '^[0-9.]+$'; then
            echo "wg preStart: DNS ready after $i attempt(s)" >&2
            exit 0
          fi
          sleep 2
        done
        echo "wg preStart: DNS still not resolving after 120s, letting wg-up retry take over" >&2
        exit 0
      '';
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "15s";
        TimeoutStartSec = "300s";
      };
      # StartLimitIntervalSec lives in [Unit], not [Service]. Previously it
      # was in serviceConfig and systemd silently ignored it (see journalctl
      # warnings). Setting it to 0 disables the default "5 failures in 10min
      # then give up" and lets wg keep retrying forever.
      unitConfig = {
        StartLimitIntervalSec = 0;
      };
    };

    radarr = vpnBound {};
    sonarr = vpnBound {};
    prowlarr = vpnBound {};
    lidarr = vpnBound {};
    transmission = vpnBound {};
    flaresolverr = vpnBound {
      vpnConfinement = {
        enable = true;
        vpnNamespace = "wg";
      };
    };

    navidrome = {
      unitConfig.RequiresMountsFor = ["/data/fun/library/music"];
      # NixOS module defaults PrivateUsers=true, which drops supplementary
      # groups. Lidarr writes into library/music as itself with group
      # `media`; without the group, Navidrome cannot read those files
      # when they are not world-readable.
      serviceConfig.PrivateUsers = lib.mkForce false;
    };

    # nixarr sandboxes ABS to its stateDir (ProtectSystem=strict). Allow
    # the library so folder watch / podcast downloads / metadata embeds
    # can write, same as Navidrome reading library/music.
    audiobookshelf = {
      unitConfig.RequiresMountsFor = [absAudiobooks absPodcasts];
      serviceConfig = {
        ReadWritePaths = [absAudiobooks absPodcasts];
        PrivateUsers = lib.mkForce false;
      };
    };

    # nixarr still execs `recyclarr sync --app-data`, which 8.6 rejects.
    # Keep its EnvironmentFile (API keys) and point CONFIG/DATA at the
    # nixarr state dir that already has the cloned guides.
    recyclarr = let
      yaml = pkgs.formats.yaml {};
      raw = yaml.generate "recyclarr-raw.yml" config.nixarr.recyclarr.configuration;
      cfg =
        pkgs.runCommand "recyclarr.yml" {
          nativeBuildInputs = [pkgs.gnused];
        } ''
          sed -E "s/[\"']!env_var ([^\"']+)[\"']/!env_var \\1/g" ${raw} > "$out"
        '';
    in {
      environment = {
        RECYCLARR_CONFIG_DIR = "/var/lib/nixarr/recyclarr";
        RECYCLARR_DATA_DIR = "/var/lib/nixarr/recyclarr";
      };
      serviceConfig.ExecStart = lib.mkForce [
        ""
        "${lib.getExe pkgs.recyclarr} sync --config ${cfg}"
      ];
    };

    # Poll Transmission for completed torrents tagged audiobook/podcast.
    # The torrent-done hook covers the happy path; this catches torrents
    # tagged after they finished and retries a failed hardlink.
    transmission-to-abs = {
      description = "Hardlink tagged Transmission downloads into Audiobookshelf";
      after = ["transmission.service"];
      wants = ["transmission.service"];
      serviceConfig = {
        Type = "oneshot";
        User = "transmission";
        Group = "media";
        ExecStart = lib.getExe transmissionToAbs;
        LoadCredential = "transmission-rpc:${config.sops.secrets."transmission-rpc-credentials".path}";
        Nice = 10;
        IOSchedulingClass = "idle";
      };
      unitConfig.RequiresMountsFor = [
        "/data/transmission/downloads"
        absAudiobooks
        absPodcasts
      ];
    };

    # Declarative configuration of Radarr/Sonarr state that lives in their
    # SQLite DB (and therefore can't be set via NixOS options on config.xml).
    # Runs on the host (not inside the VPN namespace) and talks to the *arr
    # HTTP APIs on loopback. Every mutator is idempotent: it GETs the current
    # value, diffs, and only PUTs when something would actually change.
    #
    # What it configures:
    #   - Ntfy Connect entry (push notifications on download/upgrade/import)
    #     Schema: src/NzbDrone.Core/Notifications/Ntfy/NtfySettings.cs
    #   - Transmission download client, fully declared:
    #       host=localhost, port=9091, category=radarr|tv-sonarr,
    #       removeCompletedDownloads=true, removeFailedDownloads=true.
    #     The seed ratio limit itself is configured on the Transmission
    #     service a few dozen lines above (seedRatioLimit = 1.0).
    arr-bootstrap = let
      bootstrap = pkgs.writeShellScript "arr-bootstrap" ''
        set -eu

        TRANSMISSION_USER=${lib.escapeShellArg vars.userName}
        TRANSMISSION_PASSWORD=$(${pkgs.jq}/bin/jq -r '."rpc-password"' ${config.sops.secrets."transmission-rpc-credentials".path})

        # ------------------------------------------------------------------
        # Helpers: wait for an *arr instance to be ready, then return apiKey.
        # ------------------------------------------------------------------
        wait_for_api() {
          local service="$1" port="$2" configFile="$3" apiVer="$4"

          # *arr writes <ApiKey> into config.xml on first launch; wait for it.
          for _ in $(seq 1 120); do
            if [ -f "$configFile" ] && ${pkgs.gnugrep}/bin/grep -q '<ApiKey>' "$configFile"; then
              break
            fi
            sleep 1
          done
          local apiKey
          apiKey=$(${pkgs.gnused}/bin/sed -n 's|.*<ApiKey>\(.*\)</ApiKey>.*|\1|p' "$configFile")

          # Wait until HTTP API actually responds (service may still be booting).
          for _ in $(seq 1 120); do
            if ${pkgs.curl}/bin/curl -fsS -H "X-Api-Key: $apiKey" \
                 "http://127.0.0.1:$port/api/$apiVer/system/status" >/dev/null 2>&1; then
              break
            fi
            sleep 1
          done

          printf '%s' "$apiKey"
        }

        # ------------------------------------------------------------------
        # Mutator: Transmission download client (full declaration).
        # Upserts a named "Transmission" client pointing at localhost:9091
        # (Radarr/Sonarr both run in the wg netns alongside Transmission,
        # so loopback works). `appFields` is a JSON array of app-specific
        # fields that differ between Radarr and Sonarr:
        #   Radarr: movieCategory / recentMoviePriority / olderMoviePriority
        #   Sonarr: tvCategory    / recentTvPriority    / olderTvPriority
        # Categories cause Radarr/Sonarr to drop each torrent into
        # /data/transmission/downloads/<category>/, keeping import scans
        # cleanly partitioned. Priority 0 = "Last" (queue behind anything
        # the user manually added), which is the correct default for
        # automated downloads.
        # ------------------------------------------------------------------
        upsert_download_client() {
          local service="$1" port="$2" apiKey="$3" appFields="$4" apiVer="$5"

          local payload
          payload=$(${pkgs.jq}/bin/jq -n \
            --argjson appFields "$appFields" \
            --arg username "$TRANSMISSION_USER" \
            --arg password "$TRANSMISSION_PASSWORD" \
            '{
              name: "Transmission",
              enable: true,
              protocol: "torrent",
              priority: 1,
              removeCompletedDownloads: true,
              removeFailedDownloads: true,
              implementation:     "Transmission",
              implementationName: "Transmission",
              configContract:     "TransmissionSettings",
              fields: ([
                {name: "host",      value: "localhost"},
                {name: "port",      value: 9091},
                {name: "useSsl",    value: false},
                {name: "urlBase",   value: "/transmission/"},
                {name: "username",  value: $username},
                {name: "password",  value: $password},
                {name: "directory", value: ""},
                {name: "addPaused", value: false}
              ] + $appFields),
              tags: []
            }')

          local existing
          existing=$(${pkgs.curl}/bin/curl -fsS -H "X-Api-Key: $apiKey" \
            "http://127.0.0.1:$port/api/$apiVer/downloadclient" \
            | ${pkgs.jq}/bin/jq -r \
                '.[] | select(.implementation=="Transmission") | .id // empty' \
            | head -n1)

          if [ -n "$existing" ]; then
            echo "[$service] download client: updating Transmission (id=$existing)"
            echo "$payload" | ${pkgs.jq}/bin/jq --argjson id "$existing" '. + {id: $id}' \
              | ${pkgs.curl}/bin/curl -fsS -X PUT \
                  -H "X-Api-Key: $apiKey" \
                  -H "Content-Type: application/json" \
                  --data-binary @- \
                  "http://127.0.0.1:$port/api/$apiVer/downloadclient/$existing" >/dev/null
          else
            echo "[$service] download client: creating Transmission"
            echo "$payload" | ${pkgs.curl}/bin/curl -fsS -X POST \
                -H "X-Api-Key: $apiKey" \
                -H "Content-Type: application/json" \
                --data-binary @- \
                "http://127.0.0.1:$port/api/$apiVer/downloadclient" >/dev/null
          fi
        }

        # Recyclarr TRaSH profiles reset language to Original, which
        # hard-filters instead of scoring. Set Any so "Language: Not
        # Original" can prefer the title's original audio without
        # blocking a dub when original is missing. Skip anime.
        set_radarr_language_any() {
          local port="$1" apiKey="$2"
          local anyId
          anyId=$(${pkgs.curl}/bin/curl -fsS -H "X-Api-Key: $apiKey" \
            "http://127.0.0.1:$port/api/v3/language" \
            | ${pkgs.jq}/bin/jq -r '.[] | select(.name=="Any") | .id')
          if [ -z "$anyId" ]; then
            echo "[radarr] language Any: id not found, skipping" >&2
            return 0
          fi

          local profiles
          profiles=$(${pkgs.curl}/bin/curl -fsS -H "X-Api-Key: $apiKey" \
            "http://127.0.0.1:$port/api/v3/qualityprofile")

          local -a payloads
          mapfile -t payloads < <(echo "$profiles" | ${pkgs.jq}/bin/jq -c --argjson anyId "$anyId" '
            .[]
            | select(.name | test("Anime"; "i") | not)
            | select(.language.name != "Any")
            | .language = {id: $anyId, name: "Any"}
          ')
          for payload in "''${payloads[@]}"; do
            id=$(echo "$payload" | ${pkgs.jq}/bin/jq -r '.id')
            name=$(echo "$payload" | ${pkgs.jq}/bin/jq -r '.name')
            echo "[radarr] quality profile: $name language -> Any"
            echo "$payload" | ${pkgs.curl}/bin/curl -fsS -X PUT \
              -H "X-Api-Key: $apiKey" \
              -H "Content-Type: application/json" \
              --data-binary @- \
              "http://127.0.0.1:$port/api/v3/qualityprofile/$id" >/dev/null
          done
        }

        # ------------------------------------------------------------------
        # Main: configure one *arr instance end-to-end.
        # ------------------------------------------------------------------
        configure() {
          local service="$1" port="$2" configFile="$3" appFields="$4" apiVer="$5"
          local apiKey
          apiKey=$(wait_for_api "$service" "$port" "$configFile" "$apiVer")
          upsert_download_client "$service" "$port" "$apiKey" "$appFields" "$apiVer"
          if [ "$service" = radarr ]; then
            set_radarr_language_any "$port" "$apiKey"
          fi
        }

        RADARR_FIELDS='[
          {"name":"movieCategory",       "value":"radarr"},
          {"name":"recentMoviePriority", "value":0},
          {"name":"olderMoviePriority",  "value":0}
        ]'
        SONARR_FIELDS='[
          {"name":"tvCategory",        "value":"tv-sonarr"},
          {"name":"recentTvPriority",  "value":0},
          {"name":"olderTvPriority",   "value":0}
        ]'
        LIDARR_FIELDS='[
          {"name":"musicCategory",        "value":"lidarr"},
          {"name":"recentMusicPriority",  "value":0},
          {"name":"olderMusicPriority",   "value":0}
        ]'

        # Radarr/Sonarr expose API v3; Lidarr is still on API v1.
        configure radarr 7878 /var/lib/nixarr/radarr/config.xml "$RADARR_FIELDS" v3
        configure sonarr 8989 /var/lib/nixarr/sonarr/config.xml "$SONARR_FIELDS" v3
        configure lidarr 8686 /var/lib/nixarr/lidarr/config.xml "$LIDARR_FIELDS" v1
      '';
    in {
      description = "Declaratively configure Radarr/Sonarr/Lidarr runtime state (Transmission download client)";
      after = ["radarr.service" "sonarr.service" "lidarr.service" "recyclarr.service"];
      wants = ["radarr.service" "sonarr.service" "lidarr.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = bootstrap;
        # Retry the whole bootstrap a few times if *arr isn't healthy yet.
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };
  };

  nixpkgs.config.packageOverrides = pkgs: {
    intel-vaapi-driver = pkgs.intel-vaapi-driver.override {enableHybridCodec = true;};
  };

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-compute-runtime # OpenCL filter support (hardware tonemapping and subtitle burn-in)
      intel-media-driver
      libvdpau-va-gl
      intel-vaapi-driver
      libva-vdpau-driver
    ];
  };

  environment.systemPackages = with pkgs;
    [
      # To enable `intel_gpu_top`
      intel-gpu-tools
      # because nixarr does not include it by default
      wireguard-tools
    ]
    ++ [transmissionToAbs];

  services.nginx = {
    virtualHosts = {
      "watch.adnanshaikh.com" = {
        forceSSL = true;
        useACMEHost = "adnanshaikh.com";
        locations."/" = {
          recommendedProxySettings = true;
          proxyPass = "http://127.0.0.1:8096";
        };
      };

      "prowlarr.adnanshaikh.com" = {
        forceSSL = true;
        useACMEHost = "adnanshaikh.com";
        locations."/" = {
          recommendedProxySettings = true;
          proxyPass = "http://127.0.0.1:9696";
        };
      };

      "radarr.adnanshaikh.com" = {
        forceSSL = true;
        useACMEHost = "adnanshaikh.com";
        locations."/" = {
          recommendedProxySettings = true;
          proxyPass = "http://127.0.0.1:7878";
        };
      };

      "sonarr.adnanshaikh.com" = {
        forceSSL = true;
        useACMEHost = "adnanshaikh.com";
        locations."/" = {
          recommendedProxySettings = true;
          proxyPass = "http://127.0.0.1:8989";
        };
      };

      "lidarr.adnanshaikh.com" = {
        forceSSL = true;
        useACMEHost = "adnanshaikh.com";
        locations."/" = {
          recommendedProxySettings = true;
          proxyPass = "http://127.0.0.1:8686";
        };
      };

      "music.adnanshaikh.com" = {
        forceSSL = true;
        useACMEHost = "adnanshaikh.com";
        locations."/" = {
          recommendedProxySettings = true;
          proxyWebsockets = true;
          proxyPass = "http://127.0.0.1:4533";
          extraConfig = ''
            # Streaming (Amperfy / Subsonic /rest/stream.view): do not buffer
            # the ffmpeg transcode, and do not drop a long-running play.
            proxy_buffering off;
            proxy_request_buffering off;
            proxy_read_timeout 86400s;
            proxy_send_timeout 86400s;
            client_max_body_size 50M;
          '';
        };
      };

      "listen.adnanshaikh.com" = {
        forceSSL = true;
        useACMEHost = "adnanshaikh.com";
        locations."/" = {
          recommendedProxySettings = true;
          proxyWebsockets = true;
          proxyPass = "http://127.0.0.1:${toString config.nixarr.audiobookshelf.port}";
          extraConfig = ''
            client_max_body_size 5G;
            proxy_read_timeout 86400s;
            proxy_send_timeout 86400s;
          '';
        };
      };

      "transmission.adnanshaikh.com" = {
        forceSSL = true;
        useACMEHost = "adnanshaikh.com";
        locations."/" = {
          proxyPass = "http://127.0.0.1:9091";
        };
      };
    };
  };

  # Create a shared group for media services
  users.groups.media = {};

  # Add all nixarr service users to the media group
  users.users.radarr.extraGroups = ["media"];
  users.users.sonarr.extraGroups = ["media"];
  users.users.prowlarr.extraGroups = ["media"];
  users.users.lidarr.extraGroups = ["media"];
  users.users.transmission.extraGroups = ["media"];
  users.users.jellyfin.extraGroups = ["media"];
  users.users.navidrome.extraGroups = ["media"];
  users.users.audiobookshelf.extraGroups = ["media"];

  systemd = {
    tmpfiles.rules = [
      "d /var/lib/nixarr 0755 root root"
      "d /data/transmission/downloads 2775 transmission media -"
      "d /data/transmission/downloads/radarr 2775 transmission media -"
      "d /data/transmission/downloads/tv-sonarr 2775 transmission media -"
      "d /data/transmission/downloads/lidarr 2775 transmission media -"
      # nixarr writes these as root:640; recyclarr-setup runs as
      # recyclarr and has been failing nightly since mid-September.
      "d /var/lib/nixarr/api-keys 0750 root recyclarr -"
      "z /var/lib/nixarr/api-keys/radarr.key 0640 root recyclarr -"
      "z /var/lib/nixarr/api-keys/sonarr.key 0640 root recyclarr -"
    ];

    timers.transmission-to-abs = {
      description = "Sweep tagged Transmission downloads into Audiobookshelf";
      wantedBy = ["timers.target"];
      after = ["transmission.service"];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "1min";
        AccuracySec = "15s";
        Persistent = true;
      };
    };

    #services = {
    #  "backup-nixarr" = {
    #    description = "Backup Nixarr installation with Kopia";
    #    wantedBy = ["default.target"];
    #    serviceConfig = {
    #      User = "root";
    #      ExecStartPre = "${pkgs.kopia}/bin/kopia repository connect from-config --token-file ${config.sops.secrets."kopia-repository-token".path}";
    #      ExecStart = "${pkgs.kopia}/bin/kopia snapshot create /var/lib/nixarr";
    #      ExecStartPost = "${pkgs.kopia}/bin/kopia repository disconnect";
    #    };
    #  };
    #};

    #timers = {
    #  "backup-nixarr" = {
    #    description = "Backup Nixarr installation with Kopia";
    #    wantedBy = ["timers.target"];
    #    timerConfig = {
    #      OnCalendar = "*-*-* 4:00:00";
    #      RandomizedDelaySec = "1h";
    #    };
    #  };
    #};
  };

  environment.persistence."/nix/persist" = {
    directories = [
      "/var/lib/nixarr"
      "/var/lib/navidrome"
    ];
  };
}
