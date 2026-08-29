{
  services.nginx = {
    enable = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;
  };

  # nginx terminates every vhost, including jail origins. Cap it so a
  # public flood cannot take the rest of the host with it.
  systemd.services.nginx.serviceConfig = {
    MemoryMax = "512M";
    MemoryHigh = "384M";
    MemorySwapMax = "0";
    CPUQuota = "200%";
    TasksMax = 256;
  };
}
