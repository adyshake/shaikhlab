{
  imports = [
    ./_acme.nix
    ./_nginx.nix
    ./_cloudflared.nix
    ./../modules/nixos/public-jail.nix
  ];

  shaikhlab.publicJails.wastebin = {
    enable = true;
    id = 10;
    guestPort = 8088;
    proxyPort = 18088;
    domain = "paste.adnanshaikh.com";
    public = true;
    memoryMax = "256M";
    tmpfsSize = "32M";
    maxBodySize = "128k";
    guest = {
      services.wastebin = {
        enable = true;
        settings = {
          WASTEBIN_ADDRESS_PORT = "0.0.0.0:8088";
          WASTEBIN_BASE_URL = "https://paste.adnanshaikh.com";
          WASTEBIN_TITLE = "paste";
          WASTEBIN_THEME = "ayu";
          WASTEBIN_DATABASE_PATH = ":memory:";
          WASTEBIN_MAX_BODY_SIZE = 131072;
          WASTEBIN_HTTP_TIMEOUT = 5;
          WASTEBIN_CACHE_SIZE = 32;
          # 1 hour, 1 day (default), 7 days. Nothing lives past a jail restart either.
          WASTEBIN_PASTE_EXPIRATIONS = "1h,1d=d,7d";
        };
      };
    };
  };
}
