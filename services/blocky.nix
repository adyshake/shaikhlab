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
                reuters.com
                apnews.com
                aljazeera.com
                bloomberg.com
                nytimes.com
                cnn.com
                washingtonpost.com
                foxnews.com
                nbcnews.com
                usatoday.com
                nypost.com
                npr.org
                bbc.com
                bbc.co.uk
                theguardian.com
                dailymail.co.uk
                telegraph.co.uk
                independent.co.uk
                sky.com
                wsj.com
                forbes.com
                cnbc.com
                ft.com
                businessinsider.com
                wired.com
                theverge.com
                arstechnica.com
                cnet.com
                techcrunch.com
                news.google.com
                yahoo.com
                msn.com
                indiatimes.com
                ndtv.com
                hindustantimes.com
                thehindu.com
                indianexpress.com
                indiatoday.in
                news18.com
                livemint.com
                economictimes.com
                moneycontrol.com
                india.com
                abplive.com
                aajtak.in
                firstpost.com
                scroll.in
                thewire.in
                theprint.in
                outlookindia.com
                business-standard.com
                timesnownews.com
                republicworld.com
                thequint.com
                jagran.com
                bhaskar.com
                amarujala.com
                deccanherald.com
                newindianexpress.com
                financialexpress.com
                oneindia.com
                dnaindia.com
              ''
            ];
            distractions = [
              ''
                news.ycombinator.com
                reddit.com
                instagram.com
                facebook.com
                twitter.com
                x.com
                twitch.tv
                tiktok.com
              ''
            ];
        };
        
        # Default blocking policy
        clientGroupsBlock = {
          default = [ "ads" "porn" ];
          "100.122.173.69" = [ "ads" "porn" "news" "distractions" ]; #iphone1shaikh
          "100.91.170.46" = [ "ads" "porn" "news" "distractions" ]; #mac1shaikh
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

