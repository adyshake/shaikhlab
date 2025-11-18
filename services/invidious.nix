{
  config,
  pkgs,
  ...
}: {
  services.invidious = {
    enable = true;
    port = 3001;
    settings = {
      db.user = "invidious";
      # Set external port to help with video playback
      external_port = 3001;
      # Use a modern user agent to avoid 403 errors
      user_agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";
      # Enable HTTPS-only mode if using reverse proxy
      https_only = false;
      # Disable video proxying by default (can be enabled per-user in preferences)
      # This helps avoid IP blocking issues
      proxy_videos = false;
    };
  };
}

