{
  imports = [./_acme.nix];

  services.nginx = {
    enable = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;

    # First matching TLS server was git.adnanshaikh.com, so unknown Host
    # headers (beancount after Fava was removed, typos, probes) served Forgejo.
    virtualHosts."_" = {
      default = true;
      addSSL = true;
      useACMEHost = "adnanshaikh.com";
      locations."/".return = "404";
    };
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
