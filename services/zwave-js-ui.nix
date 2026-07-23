{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  serialPort = "/dev/serial/by-id/usb-Zooz_800_Z-Wave_Stick_533D004242-if00";
  zwaveExternalSettings = config.sops.templates."zwave-js-settings".path;

  # nixos-25.11 ships zwave-js-ui 11.7.0, which predates ZWAVE_EXTERNAL_SETTINGS
  # (added in 11.11.0). Without it the declaratively-rendered security keys below
  # are ignored and must be entered by hand. Pull the package from unstable, which
  # carries a release new enough to honor the external settings file.
  #
  # TODO: remove this override (and the `package =` line below) once we upgrade to
  # nixos-26.05, which already ships a new-enough zwave-js-ui (11.18.0).
  pkgs-unstable = import inputs.nixpkgs-unstable {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
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
      # Expose the Z-Wave JS websocket server for Home Assistant's zwave_js
      # integration. 3050 to avoid Grafana (3000) and Forgejo (3001).
      serverEnabled = true;
      serverPort = 3050;
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
    # zwave-js-ui runs as a DynamicUser and can't read a root-only 0400 file.
    # Expose it via a dedicated group (see SupplementaryGroups below) rather than
    # making the security keys world-readable.
    group = "zwave-secrets";
    mode = "0440";
  };

  users.groups.zwave-secrets = {};

  services.zwave-js-ui = {
    enable = true;
    package = pkgs-unstable.zwave-js-ui;
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
    # Join zwave-secrets so the DynamicUser can read the rendered settings file.
    SupplementaryGroups = lib.mkAfter ["zwave-secrets"];
    restartTriggers = [config.sops.secrets."zwave-s0-legacy".sopsFile];
  };

  # Persist the store across reboots on this tmpfs-root host. DynamicUser +
  # StateDirectory puts it at /var/lib/private/zwave-js-ui; without this the
  # settings, node database, and connectors are wiped on every reboot.
  #
  # NOTE: /var/lib/private must be 0700 or systemd refuses to set up the
  # StateDirectory. impermanence mirrors the runtime dir's mode from the persist
  # source, so this required a one-time fix on the host (auto-created at 0755):
  #   sudo chmod 0700 /nix/persist/var/lib/private
  # After that every activation syncs /var/lib/private back to 0700 on its own.
  environment.persistence."/nix/persist".directories = [
    "/var/lib/private/zwave-js-ui"
  ];

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
