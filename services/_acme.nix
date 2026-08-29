{config, ...}: {
  sops.secrets = {
    "cloudflare-api-email" = {};
    "cloudflare-api-key" = {};
  };

  # inspo: https://carjorvaz.com/posts/setting-up-wildcard-lets-encrypt-certificates-on-nixos/
  security.acme = {
    acceptTerms = true;
    defaults.email = "admin+acme@adnanshaikh.com";

    certs."adnanshaikh.com" = {
      domain = "adnanshaikh.com";
      extraDomainNames = ["*.adnanshaikh.com"];
      dnsProvider = "cloudflare";
      dnsPropagationCheck = true;
      # inspo: https://go-acme.github.io/lego/dns/cloudflare/
      credentialFiles = {
        "CLOUDFLARE_DNS_API_TOKEN_FILE" = config.sops.secrets."cloudflare-api-key".path;
      };
    };
  };

  users.users.nginx.extraGroups = ["acme"];

  # ACME is DNS-01, so 80 is not needed on the WAN. nginx 80/443 is for
  # Tailscale/Blocky hostnames only; public hosts go through cloudflared on
  # localhost. Opening 80/443 on every interface would let LAN/WAN skip CF.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [
    80
    443
  ];

  environment.persistence."/nix/persist" = {
    directories = [
      "/var/lib/acme"
    ];
  };
}
