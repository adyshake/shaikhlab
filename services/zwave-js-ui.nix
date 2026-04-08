{...}: {
  # Zooz 800 Z-Wave stick (see /dev/serial/by-id/ on svr1shaikh).
  services.zwave-js-ui = {
    enable = true;
    serialPort = "/dev/serial/by-id/usb-Zooz_800_Z-Wave_Stick_533D004242-if00";
    settings = {
      HOST = "127.0.0.1";
      PORT = "8091";
    };
  };
}
