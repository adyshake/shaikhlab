{
  config,
  lib,
  ...
}: let
  serialPort = "/dev/serial/by-id/usb-Zooz_800_Z-Wave_Stick_533D004242-if00";
  zwaveExternalSettings = config.sops.templates."zwave-js-settings".path;
in {
  imports = [
    ./_acme.nix
    ./_nginx.nix
  ];

  # Add to secrets.yaml (32 hex chars each: openssl rand -hex 16):
  # zwave-s0-legacy, zwave-s2-unauthenticated, zwave-s2-authenticated, zwave-s2-access-control,
  # zwave-s2-authenticated-long-range, zwave-s2-access-control-long-range
  sops.secrets = {
    "zwave-s0-legacy" = {};
    "zwave-s2-unauthenticated" = {};
    "zwave-s2-authenticated" = {};
    "zwave-s2-access-control" = {};
    "zwave-s2-authenticated-long-range" = {};
    "zwave-s2-access-control-long-range" = {};
  };

  # Rendered at activation so secrets never hit the Nix store. Fields here are treated as
  # externally managed (locked in the Z-Wave JS UI settings panel).
  sops.templates."zwave-js-settings" = {
    content = builtins.toJSON {
      rf = {region = 1;};
      securityKeys = {
        S0_Legacy = config.sops.placeholder."zwave-s0-legacy";
        S2_Unauthenticated = config.sops.placeholder."zwave-s2-unauthenticated";
        S2_Authenticated = config.sops.placeholder."zwave-s2-authenticated";
        S2_AccessControl = config.sops.placeholder."zwave-s2-access-control";
      };
      securityKeysLongRange = {
        S2_Authenticated = config.sops.placeholder."zwave-s2-authenticated-long-range";
        S2_AccessControl = config.sops.placeholder."zwave-s2-access-control-long-range";
      };
    };
    owner = "root";
    mode = "0400";
  };

  services.zwave-js-ui = {
    enable = true;
    inherit serialPort;
    settings = {
      HOST = "127.0.0.1";
      PORT = "8091";
      ZWAVE_PORT = serialPort;
      ZWAVE_EXTERNAL_SETTINGS = zwaveExternalSettings;
    };
  };

  # zwave-js-ui runs under RootDirectory=%t/zwave-js-ui with only /nix/store bind-mounted;
  # expose the rendered JSON so ZWAVE_EXTERNAL_SETTINGS is readable inside the chroot.
  systemd.services.zwave-js-ui.serviceConfig = {
    BindReadOnlyPaths = lib.mkAfter [zwaveExternalSettings];
    restartTriggers = [config.sops.secrets."zwave-s0-legacy".sopsFile];
  };

  services.nginx.virtualHosts."zwave.adnanshaikh.com" = {
    forceSSL = true;
    useACMEHost = "adnanshaikh.com";
    locations."/" = {
      recommendedProxySettings = true;
      proxyPass = "http://127.0.0.1:8091";
      extraConfig = ''
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };
}
