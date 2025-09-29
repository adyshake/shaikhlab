{
  config,
  pkgs,
  lib,
  ...
}: {
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
          "watch.adnanshaikh.com" = {
            service = "http://localhost:8096";
          };
        };
      };
    };
  };

  systemd.services = {
    "cloudflared-route-tunnel" = {
      description = "Point traffic to tunnel subdomain";
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
        # workaround to ensure dns is available before setting up cloudflare tunnel
        # inspo: chatgpt
        ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in {1..10}; do ${pkgs.iputils}/bin/ping -c1 api.cloudflare.com && exit 0 || sleep 3; done; exit 1'";
        ExecStart = "${lib.getExe pkgs.cloudflared} tunnel route dns 'shaikhlab-01' 'watch.adnanshaikh.com'";
      };
    };
  };
}
