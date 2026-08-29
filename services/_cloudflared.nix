{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkOption types;
  tunnelName = "shaikhlab-01";
  ingress = config.shaikhlab.publicIngress;
  routeUnit = hostname: "cloudflared-route-${lib.head (lib.splitString "." hostname)}";
in {
  # Hostnames that must be reachable from the public internet.
  # Everything else on *.adnanshaikh.com stays LAN/Tailscale-only via blocky.
  # Jails set this via shaikhlab.publicJails.<name>.public.
  options.shaikhlab.publicIngress = mkOption {
    type = types.attrsOf (types.submodule {
      options.service = mkOption {
        type = types.str;
        example = "http://127.0.0.1:2586";
        description = "cloudflared origin URL.";
      };
    });
    default = {};
    description = "Public hostnames routed through the shaikhlab-01 Cloudflare tunnel.";
  };

  config = {
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
        ${tunnelName} = {
          credentialsFile = config.sops.secrets."cloudflare-tunnel".path;
          default = "http_status:404";
          ingress =
            lib.mapAttrs (_host: cfg: {service = cfg.service;}) ingress;
        };
      };
    };

    systemd.services =
      {
        "cloudflared-tunnel-${tunnelName}".serviceConfig = {
          MemoryMax = "256M";
          MemoryHigh = "192M";
          MemorySwapMax = "0";
          CPUQuota = "100%";
          TasksMax = 64;
        };
      }
      // lib.mapAttrs' (
        hostname: _:
          lib.nameValuePair (routeUnit hostname) {
            description = "Point ${hostname} at the ${tunnelName} tunnel";
            after = [
              "network-online.target"
              "cloudflared-tunnel-${tunnelName}.service"
            ];
            wants = [
              "network-online.target"
              "cloudflared-tunnel-${tunnelName}.service"
            ];
            wantedBy = ["default.target"];
            serviceConfig = {
              Type = "oneshot";
              ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in {1..10}; do ${pkgs.iputils}/bin/ping -c1 api.cloudflare.com && exit 0 || sleep 3; done; exit 1'";
              ExecStart = "${lib.getExe pkgs.cloudflared} tunnel route dns '${tunnelName}' '${hostname}'";
            };
          }
      )
      ingress;
  };
}
