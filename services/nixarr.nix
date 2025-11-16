{
  config,
  pkgs,
  vars,
  lib,
  ...
}: {
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
    stateDir = "/data/nixarr";

    jellyfin.enable = true;
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

    recyclarr = {
      enable = true;
      configuration = {
        sonarr = {
          anime-sonarr-v4 = {
            base_url = "https://sonarr.adnanshaikh.com";
            api_key = "!env_var SONARR_API_KEY";

            delete_old_custom_formats = true;
            replace_existing_custom_formats = true;

            include = [
              { template = "sonarr-quality-definition-anime"; }
              { template = "sonarr-v4-quality-profile-anime"; }
              { template = "sonarr-v4-custom-formats-anime"; }
            ];
          };

          web-1080p-v4 = {
            base_url = "https://sonarr.adnanshaikh.com";
            api_key = "!env_var SONARR_API_KEY";

            include = [
              { template = "sonarr-quality-definition-series"; }
              { template = "sonarr-v4-quality-profile-web-1080p"; }
              { template = "sonarr-v4-custom-formats-web-1080p"; }
            ];

            custom_formats = [
              # Unwanted
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

            include = [
              { template = "radarr-quality-profile-anime"; }
              { template = "radarr-custom-formats-anime"; }
            ];

            delete_old_custom_formats = true;
            replace_existing_custom_formats = true;

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

          hd-blueray-web = {
            base_url = "https://radarr.adnanshaikh.com";
            api_key = "!env_var RADARR_API_KEY";

            include = [
              { template = "radarr-quality-definition-movie"; }
              { template = "radarr-quality-profile-hd-blueray-web"; }
              { template = "radarr-custom-formats-hd-blueray-web"; }
            ];

            delete_old_custom_formats = true;
            replace_existing_custom_formats = true;

            custom_formats = [
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

          remux-web-1080p = {
            base_url = "https://radarr.adnanshaikh.com";
            api_key = "!env_var RADARR_API_KEY";

            include = [
              { template = "radarr-quality-definition-movie"; }
              { template = "radarr-quality-profile-remux-web-1080p"; }
              { template = "radarr-custom-formats-remux-web-1080p"; }
            ];

            delete_old_custom_formats = true;
            replace_existing_custom_formats = true;

            custom_formats = [
              {
                trash_ids = [
                  "496f355514737f7d83bf7aa4d24f8169" # TrueHD Atmos
                  "2f22d89048b01681dde8afe203bf2e95" # DTS X
                  "417804f7f2c4308c1f4c5d380d4c4475" # ATMOS (undefined)
                  "1af239278386be2919e1bcee0bde047e" # DD+ ATMOS
                  "3cafb66171b47f226146a0770576870f" # TrueHD
                  "dcf3ec6938fa32445f590a4da84256cd" # DTS-HD MA
                  "a570d4a0e56a2874b64e5bfa55202a1b" # FLAC
                  "e7c2fcae07cbada050a0af3357491d7b" # PCM
                  "8e109e50e0a0b83a5098b056e13bf6db" # DTS-HD HRA
                  "185f1dd7264c4562b9022d963ac37424" # DD+
                  "f9f847ac70a0af62ea4a08280b859636" # DTS-ES
                  "1c1a4c5e823891c75bc50380a6866f73" # DTS
                  "240770601cc226190c367ef59aba7463" # AAC
                  "c2998bd0d90ed5621d8df281e839436e" # DD
                ];
                assign_scores_to = [ { name = "Remux + WEB 1080p"; } ];
              }
              {
                trash_ids = [
                  "dc98083864ea246d05a42df0d05f81cc" # x265 (HD)
                  "839bea857ed2c0a8e084f3cbdbd65ecb" # x265 (no HDR/DV)
                ];
                assign_scores_to = [
                  {
                    name = "Remux + WEB 1080p";
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
      extraAllowedIps = [ "100.64.0.0/10" ];
      extraSettings = {
        peer-limit-global = 500;
        cache-size-mb = 256;
        download-dir = "/data/transmission";
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
        # todo: figure out how to integrate rpc-password into sops-nix
        rpc-password = "{7d827abfb09b77e45fe9e72d97956ab8fb53acafoPNV1MpJ";
      };
    };

    vpn = {
      enable = true;
      wgConf = config.sops.secrets."wg.conf".path;
    };
  };

  systemd.services.flaresolverr.vpnConfinement = {
    enable = true;
    vpnNamespace = "wg";
  };

  services.flaresolverr.enable = true;

  nixpkgs.config.packageOverrides = pkgs: {
    vaapiIntel = pkgs.vaapiIntel.override {enableHybridCodec = true;};
  };

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-compute-runtime # OpenCL filter support (hardware tonemapping and subtitle burn-in)
      intel-media-driver
      libvdpau-va-gl
      vaapiIntel
      vaapiVdpau
    ];
  };

  environment.systemPackages = with pkgs; [
    # To enable `intel_gpu_top`
    intel-gpu-tools
    # because nixarr does not include it by default
    wireguard-tools
  ];

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

      "transmission.adnanshaikh.com" = {
        forceSSL = true;
        useACMEHost = "adnanshaikh.com";
        locations."/" = {
          proxyPass = "http://127.0.0.1:9091";
        };
      };
    };
  };

  systemd = {
    tmpfiles.rules = [
      "d /data/nixarr 0755 root root"
      "d /data/transmission 0755 root root"
      "d /data/transmission/.incomplete 0755 root root"
    ];

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
      # Note: /data/nixarr and /data/transmission are on the RAID array,
      # so they don't need to be persisted via impermanence
    ];
  };
}
