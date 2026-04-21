{
  config,
  pkgs,
  lib,
  ...
}: {
  # Only hostnames that must be reachable from the public internet live here.
  # Everything else on *.adnanshaikh.com stays LAN/Tailscale-only via blocky
  # (see services/blocky.nix customDNS).

  sops.secrets = {
    "cloudflare-tunnel" = {
      format = "binary";
      sopsFile = ./../secrets/cloudflare-tunnel;
    };
    "cloudflare-token" = {
      format = "binary";
      sopsFile = ./../secrets/cloudflare-cert.pem;
    };
  };

  environment.etc."cloudflared/cert.pem".source = config.sops.secrets."cloudflare-token".path;

  services.cloudflared = {
    enable = true;
    tunnels = {
      "shaikhlab-01" = {
        credentialsFile = config.sops.secrets."cloudflare-tunnel".path;
        default = "http_status:404";
        ingress = {
          # Required so Radarr/Sonarr (which run inside the WireGuard VPN
          # namespace and cannot reach blocky/Tailscale) can resolve and reach
          # the ntfy server when publishing "Import Complete" notifications.
          "ntfy.adnanshaikh.com" = {
            service = "http://localhost:2586";
          };
        };
      };
    };
  };

  # Point the public Cloudflare DNS record at the tunnel. One oneshot per host.
  # `ExecStartPre` waits for network/DNS before touching the Cloudflare API.
  systemd.services.cloudflared-route-ntfy = {
    description = "Point ntfy.adnanshaikh.com at the shaikhlab tunnel";
    after = [
      "network-online.target"
      "cloudflared-tunnel-shaikhlab-01.service"
    ];
    wants = [
      "network-online.target"
      "cloudflared-tunnel-shaikhlab-01.service"
    ];
    wantedBy = ["default.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in {1..10}; do ${pkgs.iputils}/bin/ping -c1 api.cloudflare.com && exit 0 || sleep 3; done; exit 1'";
      ExecStart = "${lib.getExe pkgs.cloudflared} tunnel route dns 'shaikhlab-01' 'ntfy.adnanshaikh.com'";
    };
  };
}
