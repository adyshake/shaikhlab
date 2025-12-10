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

    # Use latest version for best integration support
    package = pkgs.home-assistant;

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
        name = "My Nix Home";
        latitude = "40.730610"; #NYC
        longitude = "-73.935242"; #NYC
        elevation = "100";
        unit_system = "us_customary";
        time_zone = "America/Los_Angeles";
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

      # Enable Python scripts
      python_script = {};

      # Shell commands (add custom commands here as needed)
      shell_command = {};

    };
  };

  # Allow access to the Home Assistant web interface (default port 8123)
  networking.firewall.allowedTCPPorts = [8123];

  services.nginx = {
    virtualHosts = {
      "homeassistant.adnanshaikh.com" = {
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

  # environment.persistence."/nix/persist" = {
  #   directories = [
  #     "/var/lib/homeassistant"
  #   ];
  # };
}
