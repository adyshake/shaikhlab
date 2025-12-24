{
  config,
  pkgs,
  lib,
  vars,
  ...
}: let
  # Server IP address for DNS records
  serverIP = "100.72.152.7";
  stephenBlackUrl = "https://raw.githubusercontent.com/StevenBlack/hosts/master";
in {
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
            ads = ["${stephenBlackUrl}/hosts"];
            fakenews = ["${stephenBlackUrl}/alternates/fakenews-only/hosts"];
            gambling = ["${stephenBlackUrl}/alternates/gambling-only/hosts"];
            porn = ["${stephenBlackUrl}/alternates/porn-only/hosts"];
            news = [
              ''
                www.reuters.com
                www.apnews.com
                www.aljazeera.com
                www.bloomberg.com
                www.nytimes.com
                www.cnn.com
                www.washingtonpost.com
                www.foxnews.com
                www.nbcnews.com
                www.usatoday.com
                www.nypost.com
                www.npr.org
                www.bbc.com
                www.bbc.co.uk
                www.theguardian.com
                www.dailymail.co.uk
                www.telegraph.co.uk
                www.independent.co.uk
                www.sky.com
                www.wsj.com
                www.forbes.com
                www.cnbc.com
                www.ft.com
                www.businessinsider.com
                www.wired.com
                www.theverge.com
                www.arstechnica.com
                www.cnet.com
                www.techcrunch.com
                www.news.google.com
                www.yahoo.com
                www.msn.com
                www.indiatimes.com
                www.ndtv.com
                www.hindustantimes.com
                www.thehindu.com
                www.indianexpress.com
                www.indiatoday.in
                www.news18.com
                www.livemint.com
                www.economictimes.com
                www.moneycontrol.com
                www.india.com
                www.abplive.com
                www.aajtak.in
                www.firstpost.com
                www.scroll.in
                www.thewire.in
                www.theprint.in
                www.outlookindia.com
                www.business-standard.com
                www.timesnownews.com
                www.republicworld.com
                www.thequint.com
                www.jagran.com
                www.bhaskar.com
                www.amarujala.com
                www.deccanherald.com
                www.newindianexpress.com
                www.financialexpress.com
                www.oneindia.com
                www.dnaindia.com
              ''
            ];
            distractions = [
              ''
                news.ycombinator.com
                www.reddit.com
                old.reddit.com
                www.instagram.com
                www.facebook.com
                www.twitter.com
                www.x.com
                www.twitch.tv
                www.tiktok.com
              ''
            ];
        };
        
        # Default blocking policy
        clientGroupsBlock = {
          default = [ "ads" ];
          "100.122.173.69" = [ "ads" ]; #iphone1shaikh
          "100.91.170.46" = [ "ads" ]; #mac1shaikh
        };
      };

      # Optional: Cache results to speed up your phone's browsing
      caching = {
        minTime = "5m";
        maxTime = "30m";
        prefetching = true;
      };

      # For initially solving DoH/DoT Requests when no system Resolver is available.
      bootstrapDns = {
          upstream = "https://dns.quad9.net/dns-query";
          ips = [ "9.9.9.9" ];
      };

      # Custom DNS entries
      # All nginx server mappings should be added here
      customDNS = {
          mapping = {              
              # Server
              "server.adnanshaikh.com" = serverIP;
              # DNS service
              "dns.adnanshaikh.com" = serverIP;
              
              # Nixarr services
              "watch.adnanshaikh.com" = serverIP;
              "prowlarr.adnanshaikh.com" = serverIP;
              "radarr.adnanshaikh.com" = serverIP;
              "sonarr.adnanshaikh.com" = serverIP;
              "transmission.adnanshaikh.com" = serverIP;
              
              # Home Assistant
              "hass.adnanshaikh.com" = serverIP;
          };
      };
    };
  };

  # Disable systemd-resolved to allow Blocky to bind to port 53
  services.resolved.enable = false;

  # Open the DNS port in the firewall
  networking.firewall.allowedUDPPorts = [ 53 ];
  networking.firewall.allowedTCPPorts = [ 53 ];
}

