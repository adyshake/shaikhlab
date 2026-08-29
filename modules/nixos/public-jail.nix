{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.shaikhlab.publicJails;
  enabledJails = lib.filterAttrs (_: jail: jail.enable) cfg;

  # veth is ve-<name>; IFNAMSIZ is 15 chars. Keep names short.
  vethName = name: "ve-${name}";

  jailOpts = {name, ...}: {
    options = {
      enable = mkEnableOption "this public jail";

      id = mkOption {
        type = types.ints.between 1 254;
        description = ''
          Third octet of the /32 pair. Host is 10.233.<id>.1, guest is
          10.233.<id>.2. Must be unique across jails.
        '';
      };

      guestPort = mkOption {
        type = types.port;
        description = "Port the service listens on inside the jail.";
      };

      proxyPort = mkOption {
        type = types.port;
        description = ''
          Host localhost port nginx listens on for the Cloudflare origin.
          Must be unique across jails. Public/Tailscale TLS still uses 443.
        '';
      };

      domain = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "paste.adnanshaikh.com";
        description = "nginx server_name. Also used as the Cloudflare hostname when public.";
      };

      public = mkOption {
        type = types.bool;
        default = false;
        description = "Publish this jail on the Cloudflare tunnel (the only WAN door).";
      };

      memoryMax = mkOption {
        type = types.str;
        default = "256M";
        description = "cgroup memory hard cap for the whole jail (tmpfs counts).";
      };

      cpuQuota = mkOption {
        type = types.str;
        default = "50%";
        description = "cgroup CPUQuota for the jail.";
      };

      tasksMax = mkOption {
        type = types.ints.positive;
        default = 128;
        description = "cgroup TasksMax for the jail.";
      };

      tmpfsSize = mkOption {
        type = types.str;
        default = "32M";
        description = "Size of the guest /var tmpfs. This is the writable disk.";
      };

      maxBodySize = mkOption {
        type = types.str;
        default = "128k";
        description = "nginx client_max_body_size.";
      };

      rateLimit = {
        rate = mkOption {
          type = types.str;
          default = "20r/m";
          description = "Per-client nginx limit_req rate (CF-Connecting-IP, else peer).";
        };
        burst = mkOption {
          type = types.ints.positive;
          default = 40;
        };
        connections = mkOption {
          type = types.ints.positive;
          default = 8;
          description = "Per-client concurrent connections.";
        };
        globalRate = mkOption {
          type = types.str;
          default = "2r/s";
          description = "Whole-jail nginx limit_req rate.";
        };
        globalBurst = mkOption {
          type = types.ints.positive;
          default = 40;
        };
      };

      extraNginxConfig = mkOption {
        type = types.lines;
        default = "";
        description = "Extra nginx config inside the location / block.";
      };

      bindMounts = mkOption {
        type = types.attrs;
        default = {};
        description = "Passed to containers.<name>.bindMounts. Empty means the jail sees no host paths.";
      };

      guest = mkOption {
        type = types.deferredModule;
        description = ''
          NixOS module evaluated inside the jail. Enable the actual service
          here (wastebin, ntfy, …). The jail already has a private network,
          no host DNS, and a size-capped /var.
        '';
      };
    };
  };

  nginxProxy = jail: {
    recommendedProxySettings = true;
    proxyPass = "http://${jail.localAddress}:${toString jail.guestPort}";
    extraConfig = ''
      limit_req zone=jail_${jail.name}_req burst=${toString jail.rateLimit.burst} nodelay;
      limit_req zone=jail_${jail.name}_global burst=${toString jail.rateLimit.globalBurst} nodelay;
      limit_conn jail_${jail.name}_conn ${toString jail.rateLimit.connections};
      client_max_body_size ${jail.maxBodySize};
      proxy_read_timeout 15s;
      proxy_send_timeout 15s;
      proxy_connect_timeout 5s;
      add_header X-Content-Type-Options nosniff always;
      add_header X-Frame-Options DENY always;
      add_header Referrer-Policy no-referrer always;
      ${jail.extraNginxConfig}
    '';
  };

  enrich = name: jail:
    jail
    // {
      inherit name;
      hostAddress = "10.233.${toString jail.id}.1";
      localAddress = "10.233.${toString jail.id}.2";
      iface = vethName name;
    };
in {
  options.shaikhlab.publicJails = mkOption {
    type = types.attrsOf (types.submodule jailOpts);
    default = {};
    description = ''
      Hardened nspawn jails for services that may face the internet.
      Each jail has its own network namespace (no host localhost), a
      cgroup memory cap, and a size-limited tmpfs for /var. Traffic
      enters only via host nginx (rate limits, body cap), optionally
      through the Cloudflare tunnel.

      Example (ntfy later):

        shaikhlab.publicJails.ntfy = {
          enable = true;
          id = 11;
          guestPort = 2586;
          proxyPort = 12586;
          domain = "ntfy.adnanshaikh.com";
          public = true;
          guest = { ... }: { services.ntfy-sh.enable = true; ... };
        };
    '';
  };

  config = mkIf (enabledJails != {}) {
    assertions =
      [
        {
          assertion = (lib.length (lib.unique (lib.mapAttrsToList (_: j: j.id) enabledJails))) == (lib.length (lib.attrNames enabledJails));
          message = "shaikhlab.publicJails: each jail needs a unique id.";
        }
        {
          assertion = (lib.length (lib.unique (lib.mapAttrsToList (_: j: j.proxyPort) enabledJails))) == (lib.length (lib.attrNames enabledJails));
          message = "shaikhlab.publicJails: each jail needs a unique proxyPort.";
        }
      ]
      ++ (lib.mapAttrsToList (name: jail: {
          assertion = builtins.match "[a-z0-9]{1,12}" name != null;
          message = "shaikhlab.publicJails.${name}: name must be [a-z0-9] and ≤12 chars (veth is ve-<name>).";
        })
        enabledJails)
      ++ (lib.mapAttrsToList (name: jail: {
          assertion = jail.public -> jail.domain != null;
          message = "shaikhlab.publicJails.${name}: public = true requires domain.";
        })
        enabledJails);

    networking.firewall = {
      extraCommands = lib.concatStrings (lib.mapAttrsToList (
          name: jail: let
            j = enrich name jail;
          in ''
            # ${name}: host may talk to the guest; guest may not start connections to the host or LAN.
            iptables -w -I nixos-fw 1 -i ${j.iface} -m conntrack --ctstate ESTABLISHED,RELATED -j nixos-fw-accept
            iptables -w -I nixos-fw 2 -i ${j.iface} -j nixos-fw-refuse
            ip6tables -w -I nixos-fw 1 -i ${j.iface} -m conntrack --ctstate ESTABLISHED,RELATED -j nixos-fw-accept
            ip6tables -w -I nixos-fw 2 -i ${j.iface} -j nixos-fw-refuse
            iptables -w -I FORWARD 1 -i ${j.iface} -j DROP
            iptables -w -I FORWARD 2 -o ${j.iface} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
            iptables -w -I FORWARD 3 -o ${j.iface} -j DROP
          ''
        )
        enabledJails);
      extraStopCommands = lib.concatStrings (lib.mapAttrsToList (
          name: jail: let
            j = enrich name jail;
          in ''
            iptables -w -D nixos-fw -i ${j.iface} -m conntrack --ctstate ESTABLISHED,RELATED -j nixos-fw-accept 2>/dev/null || true
            iptables -w -D nixos-fw -i ${j.iface} -j nixos-fw-refuse 2>/dev/null || true
            ip6tables -w -D nixos-fw -i ${j.iface} -m conntrack --ctstate ESTABLISHED,RELATED -j nixos-fw-accept 2>/dev/null || true
            ip6tables -w -D nixos-fw -i ${j.iface} -j nixos-fw-refuse 2>/dev/null || true
            iptables -w -D FORWARD -i ${j.iface} -j DROP 2>/dev/null || true
            iptables -w -D FORWARD -o ${j.iface} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
            iptables -w -D FORWARD -o ${j.iface} -j DROP 2>/dev/null || true
          ''
        )
        enabledJails);
    };

    containers =
      lib.mapAttrs (
        name: jail: let
          j = enrich name jail;
        in {
          autoStart = true;
          ephemeral = true;
          privateNetwork = true;
          privateUsers = "pick";
          # Bare IPs: nixos-containers defaults these to /32. A CIDR suffix
          # makes the guest `ip route` setup fail ("any valid address is expected").
          hostAddress = j.hostAddress;
          localAddress = j.localAddress;
          bindMounts = jail.bindMounts;
          tmpfs = [
            "/var:size=${jail.tmpfsSize},mode=0755"
            "/tmp:size=8M,mode=1777"
          ];
          extraFlags = [
            "--no-new-privileges=yes"
          ];
          timeoutStartSec = "2min";
          config = {
            imports = [jail.guest];
            system.stateVersion = config.system.stateVersion;
            networking.useHostResolvConf = lib.mkForce false;
            networking.useDHCP = false;
            networking.firewall.enable = false;
            networking.nameservers = [];
            # Link route to the host only. A default gateway would let a
            # later `networking.nat.internalInterfaces = [ "ve-+" ]` give
            # this jail LAN/internet.
            networking.defaultGateway = lib.mkForce null;
            networking.defaultGateway6 = lib.mkForce null;
            documentation.enable = false;
            documentation.nixos.enable = false;
          };
        }
      )
      enabledJails;

    systemd.services =
      lib.mapAttrs' (
        name: jail:
          lib.nameValuePair "container@${name}" {
            serviceConfig = {
              MemoryMax = jail.memoryMax;
              MemorySwapMax = "0";
              CPUQuota = jail.cpuQuota;
              TasksMax = jail.tasksMax;
            };
          }
      )
      enabledJails;

    services.nginx = {
      enable = true;
      appendHttpConfig = ''
        limit_req_status 429;
        limit_conn_status 429;
        # Trust CF-Connecting-IP only from cloudflared (127.0.0.1). Direct
        # clients can send any value in that header; use their real peer.
        map $http_cf_connecting_ip $jail_cf_ip {
          default $http_cf_connecting_ip;
          ""      $binary_remote_addr;
        }
        map $remote_addr $jail_rl_key {
          127.0.0.1 $jail_cf_ip;
          ::1       $jail_cf_ip;
          default   $binary_remote_addr;
        }
      ''
      + lib.concatStrings (lib.mapAttrsToList (
          name: jail: ''
            limit_req_zone $jail_rl_key zone=jail_${name}_req:1m rate=${jail.rateLimit.rate};
            limit_req_zone $server_name zone=jail_${name}_global:1m rate=${jail.rateLimit.globalRate};
            limit_conn_zone $jail_rl_key zone=jail_${name}_conn:1m;
          ''
        )
        enabledJails);

      virtualHosts = lib.mkMerge (lib.mapAttrsToList (
          name: jail: let
            j = enrich name jail;
            loc = {"/" = nginxProxy j;};
            jailServerExtra = ''
              access_log off;
              error_log /dev/null crit;
              client_body_timeout 5s;
              client_header_timeout 5s;
              send_timeout 10s;
            '';
          in
            lib.optionalAttrs (jail.domain != null) {
              ${jail.domain} = {
                forceSSL = true;
                useACMEHost = "adnanshaikh.com";
                extraConfig = jailServerExtra;
                locations = loc;
              };
              "${name}-jail-origin" = {
                listen = [
                  {
                    addr = "127.0.0.1";
                    port = jail.proxyPort;
                  }
                ];
                # Only listener on this port, so Host: paste.* from cloudflared still matches.
                default = true;
                extraConfig = jailServerExtra;
                locations = loc;
              };
            }
        )
        enabledJails);
    };

    shaikhlab.publicIngress =
      lib.mapAttrs' (
        name: jail:
          lib.nameValuePair jail.domain {
            service = "http://127.0.0.1:${toString jail.proxyPort}";
          }
      ) (
        lib.filterAttrs (_: jail: jail.public && jail.domain != null) enabledJails
      );
  };
}
