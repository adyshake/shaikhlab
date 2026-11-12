{...}: let
  domain = "yattee.adnanshaikh.com";
  stateDir = "/var/lib/yattee-server";
in {
  imports = [
    ./_nginx.nix
  ];

  # Official image bundles yt-dlp, deno, and ffmpeg. YouTube's player
  # changes often enough that rebuilding those in nix is the worse option.
  # Tag is the server release; bump it when extraction starts failing.
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";
  virtualisation.oci-containers.containers.yattee-server = {
    image = "docker.io/yattee/yattee-server:1.0.10";
    ports = ["127.0.0.1:8085:8085"];
    volumes = [
      "${stateDir}/data:/app/data"
      "${stateDir}/downloads:/downloads"
    ];
    environment.SECURE_COOKIES = "true";
  };

  systemd.tmpfiles.settings.yattee-server = {
    "${stateDir}/data".d = {
      user = "root";
      group = "root";
      mode = "0750";
    };
    "${stateDir}/downloads".d = {
      user = "root";
      group = "root";
      mode = "0750";
    };
  };

  # Account, encryption key, and the pulled image. Root is tmpfs.
  environment.persistence."/nix/persist".directories = [
    stateDir
    "/var/lib/containers"
  ];

  # Tailscale-only, same as Jellyfin. First visit is the setup wizard.
  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    useACMEHost = "adnanshaikh.com";
    locations."/" = {
      recommendedProxySettings = true;
      proxyPass = "http://127.0.0.1:8085";
      extraConfig = ''
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };

  # The container's outbound path is podman0. Without this, NixOS drops
  # the YouTube requests the server is here to make.
  networking.firewall.trustedInterfaces = ["podman0"];
}
