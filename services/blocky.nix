{
  config,
  pkgs,
  lib,
  vars,
  ...
}: {
  services.blocky = {
    enable = true;
    settings = {
      ports.dns = 53; # Port to listen on (ensure this is open in firewall)
      
      # Upstream resolvers (using Cloudflare and Quad9 via HTTPS)
      upstreams.groups.default = [
        "https://one.one.one.one/dns-query"
        "https://dns.quad9.net/dns-query"
      ];

      # Distraction & Ad-blocking lists
      blocking = {
        denylists = {
          # Standard ads/trackers
          ads = [ "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts" ];
          # Distractions: You can add more lists here (e.g., social media blocks)
          distractions = [
            "https://raw.githubusercontent.com/StevenBlack/hosts/refs/heads/master/alternates/fakenews-gambling-porn-social-only/hosts"
          ];
        };
        
        # Default blocking policy
        clientGroupsBlock = {
          default = [ "ads" "distractions" ];
        };
      };

      # Optional: Cache results to speed up your phone's browsing
      caching = {
        minTime = "5m";
        maxTime = "30m";
        prefetching = true;
      };
    };
  };

  # Disable systemd-resolved to allow Blocky to bind to port 53
  services.resolved.enable = false;

  # Open the DNS port in the firewall
  networking.firewall.allowedUDPPorts = [ 53 ];
  networking.firewall.allowedTCPPorts = [ 53 ];
}

