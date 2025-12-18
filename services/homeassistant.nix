{
  config,
  pkgs,
  lib,
  vars,
  ...
}: {
  imports = [
    ./_acme.nix
    ./_nginx.nix
  ];

  # Based on: https://nixos.wiki/wiki/Home_Assistant

  services.home-assistant = {
    enable = true;
    configWritable = false;

    # Use latest version for best integration support
    package = pkgs.home-assistant;

    # Custom components from GitHub
    customComponents = [
      # Mazda Connected Services integration
      # https://github.com/fano0001/home-assistant-mazda
      (pkgs.buildHomeAssistantComponent rec {
        owner = "fano0001";
        domain = "mazda_cs";
        version = "1.8.5";
        src = pkgs.fetchFromGitHub {
          owner = "fano0001";
          repo = "home-assistant-mazda";
          rev = "v${version}";
          sha256 = "sha256-7CQM7qIBUDVSKOsgjRg+/A2h3UYoXVsC51Q5LpOBMbQ=";
        };
      })
    ];

    extraComponents = [
      # Core integrations
      "analytics"
      "google_translate"
      "met"
      "radio_browser"
      "shopping_list"
      "default_config"

      # Camera and media
      "stream"
      "ffmpeg"
      # Automation and scripting
      "python_script"
      "shell_command"
      # Recommended for fast zlib compression
      # https://www.home-assistant.io/integrations/isal
      "isal"
      
      "roborock"
    ];

    extraPackages = python3Packages: with python3Packages; [
      # Image processing
      pillow
      numpy
      opencv4
      # Radio Browser integration
      radios
      # Google Translate TTS integration
      gtts
    ];

    # This section allows you to declaratively configure Home Assistant
    # using Nix expressions instead of YAML files (like configuration.yaml)
    config = {
      # Basic configuration
      default_config = {};

      homeassistant = {
        name = "Home";
        latitude = "!secret latitude";
        longitude = "!secret longitude";
        elevation = "!secret elevation";
        unit_system = "us_customary";
        time_zone = "!secret time_zone";
      };

      # HTTP interface
      http = {
        server_port = 8123;
        use_x_forwarded_for = true;
        trusted_proxies = [
          "127.0.0.1"
          "::1"
        ];
      };

    };
  };

  # Allow access to the Home Assistant web interface (default port 8123)
  networking.firewall.allowedTCPPorts = [8123];

  services.nginx = {
    virtualHosts = {
      "hass.adnanshaikh.com" = {
        forceSSL = true;
        useACMEHost = "adnanshaikh.com";
        locations."/" = {
          recommendedProxySettings = true;
          proxyPass = "http://127.0.0.1:8123";
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
        };
      };
    };
  };

  sops.secrets."hass-secrets" = {
    format = "binary";
    sopsFile = ./../secrets/hass-secrets.yaml;
    owner = "hass";
    group = "hass";
    path = "/var/lib/hass/secrets.yaml";
    restartUnits = [ "home-assistant.service" ];
  };

  # sops.secrets."kopia-repository-token" = {};

  # systemd = {
  #   services = {
  #     "backup-homeassistant" = {
  #       description = "Backup Home Assistant installation with Kopia";
  #       wantedBy = ["default.target"];
  #       serviceConfig = {
  #         User = "root";
  #         ExecStartPre = "${pkgs.kopia}/bin/kopia repository connect from-config --token-file ${config.sops.secrets."kopia-repository-token".path}";
  #         ExecStart = "${pkgs.kopia}/bin/kopia snapshot create /var/lib/homeassistant";
  #         ExecStartPost = "${pkgs.kopia}/bin/kopia repository disconnect";
  #       };
  #     };
  #   };

  #   timers = {
  #     "backup-homeassistant" = {
  #       description = "Backup Home Assistant installation with Kopia";
  #       wantedBy = ["timers.target"];
  #       timerConfig = {
  #         OnCalendar = "*-*-* 4:00:00";
  #         RandomizedDelaySec = "1h";
  #       };
  #     };
  #   };
  # };

  # Persist Home Assistant configuration and storage
  # This ensures integrations and their configs survive reboots
  environment.persistence."/nix/persist" = {
    directories = [
      {
        directory = "/var/lib/hass";
        user = "hass";
        group = "hass";
        mode = "0700";
      }
    ];
  };
}
