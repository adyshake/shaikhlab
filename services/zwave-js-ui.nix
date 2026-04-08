{...}: {
  imports = [
    ./_acme.nix
    ./_nginx.nix
  ];

  # Zooz 800 Z-Wave stick. serialPort = DeviceAllow only; ZWAVE_PORT actually enables the driver.
  services.zwave-js-ui = {
    enable = true;
    serialPort = "/dev/serial/by-id/usb-Zooz_800_Z-Wave_Stick_533D004242-if00";;
    settings = {
      HOST = "127.0.0.1";
      PORT = "8091";
    };
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
