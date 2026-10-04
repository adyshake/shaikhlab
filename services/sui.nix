{
  pkgs,
  ...
}: let
  domain = "start.adnanshaikh.com";

  # Archived upstream; static HTML/JS only. Pin the last master commit.
  # https://github.com/jeroenpardon/sui
  suiSrc = pkgs.fetchFromGitHub {
    owner = "jeroenpardon";
    repo = "sui";
    rev = "ccb68263177a27a57fed98ee52b98e64d5462609";
    hash = "sha256-ycJk1P4R+2riQtB+laVqxe+a039OOxzBoELZ9vwkwVo=";
  };

  appsJson = pkgs.writeText "apps.json" (builtins.toJSON {
    apps = [
      {
        name = "Watch";
        url = "watch.adnanshaikh.com";
        icon = "television";
      }
      {
        name = "Music";
        url = "music.adnanshaikh.com";
        icon = "music";
      }
      {
        name = "Listen";
        url = "listen.adnanshaikh.com";
        icon = "headphones";
      }
      {
        name = "Radarr";
        url = "radarr.adnanshaikh.com";
        icon = "filmstrip";
      }
      {
        name = "Sonarr";
        url = "sonarr.adnanshaikh.com";
        icon = "television-classic";
      }
      {
        name = "Lidarr";
        url = "lidarr.adnanshaikh.com";
        icon = "album";
      }
      {
        name = "Prowlarr";
        url = "prowlarr.adnanshaikh.com";
        icon = "radar";
      }
      {
        name = "Transmission";
        url = "transmission.adnanshaikh.com";
        icon = "progress-download";
      }
      {
        name = "ntfy";
        url = "ntfy.adnanshaikh.com";
        icon = "bell-ring";
      }
      {
        name = "Home Assistant";
        url = "hass.adnanshaikh.com";
        icon = "home-assistant";
      }
      {
        name = "Z-Wave";
        url = "zwave.adnanshaikh.com";
        icon = "z-wave";
      }
      {
        name = "Grafana";
        url = "grafana.adnanshaikh.com";
        icon = "chart-areaspline";
      }
      {
        name = "Git";
        url = "git.adnanshaikh.com";
        icon = "git";
      }
      {
        name = "Paste";
        url = "paste.adnanshaikh.com";
        icon = "content-paste";
      }
      {
        name = "Photos";
        url = "photos.adnanshaikh.com";
        icon = "image";
      }
      {
        name = "Drive";
        url = "drive.adnanshaikh.com";
        icon = "folder";
      }
    ];
  });

  linksJson = pkgs.writeText "links.json" (builtins.toJSON {
    bookmarks = [
      {
        category = "Media";
        links = [
          {
            name = "Watch";
            url = "https://watch.adnanshaikh.com";
          }
          {
            name = "Music";
            url = "https://music.adnanshaikh.com";
          }
          {
            name = "Listen";
            url = "https://listen.adnanshaikh.com";
          }
          {
            name = "Radarr";
            url = "https://radarr.adnanshaikh.com";
          }
          {
            name = "Sonarr";
            url = "https://sonarr.adnanshaikh.com";
          }
          {
            name = "Lidarr";
            url = "https://lidarr.adnanshaikh.com";
          }
          {
            name = "Prowlarr";
            url = "https://prowlarr.adnanshaikh.com";
          }
          {
            name = "Transmission";
            url = "https://transmission.adnanshaikh.com";
          }
        ];
      }
      {
        category = "Home";
        links = [
          {
            name = "Home Assistant";
            url = "https://hass.adnanshaikh.com";
          }
          {
            name = "Z-Wave";
            url = "https://zwave.adnanshaikh.com";
          }
          {
            name = "ntfy";
            url = "https://ntfy.adnanshaikh.com";
          }
          {
            name = "Photos";
            url = "https://photos.adnanshaikh.com";
          }
          {
            name = "Drive";
            url = "https://drive.adnanshaikh.com";
          }
        ];
      }
      {
        category = "Lab";
        links = [
          {
            name = "Grafana";
            url = "https://grafana.adnanshaikh.com";
          }
          {
            name = "Git";
            url = "https://git.adnanshaikh.com";
          }
          {
            name = "Paste";
            url = "https://paste.adnanshaikh.com";
          }
        ];
      }
      {
        category = "Web";
        links = [
          {
            name = "Kagi Assistant";
            url = "https://assistant.kagi.com";
          }
        ];
      }
    ];
  });

  extraCss = pkgs.writeText "shaikhlab.css" ''
    :root {
      --color-background: #000000;
      --color-text-pri: #f2f2f2;
      --color-text-acc: #6e6e6e;
    }

    #modal > div {
      background-color: #111111;
      color: #f2f2f2;
    }

    #modal h1,
    #modal h2 {
      color: #f2f2f2;
    }

    .modal-close,
    .modal-close:hover {
      color: #f2f2f2;
    }

    #container {
      grid-template-rows: auto;
    }

    .theme-black {
      background-color: #000000;
      border: 4px solid #6e6e6e;
      color: #f2f2f2;
    }

    svg.icon,
    .modal-close svg,
    #modal-footer svg {
      display: inline-block;
      height: 1em;
      vertical-align: -0.15em;
      width: 1em;
    }
  '';

  suiRoot = pkgs.runCommand "sui-shaikhlab" {nativeBuildInputs = [pkgs.python3];} ''
    mkdir -p $out
    cp -r ${suiSrc}/. $out/
    chmod -R u+w $out

    cp ${extraCss} $out/assets/css/shaikhlab.css

    python3 ${./sui/patch-sui.py} $out ${appsJson} ${linksJson} ${./sui/icons.json}
  '';
in {
  imports = [
    ./_acme.nix
    ./_nginx.nix
  ];

  services.nginx.virtualHosts."${domain}" = {
    forceSSL = true;
    useACMEHost = "adnanshaikh.com";
    root = suiRoot;
    locations."/".extraConfig = ''
      try_files $uri $uri/ /index.html;
      # New tabs should reuse the last response instead of revalidating.
      add_header Cache-Control "public, max-age=3600";
    '';
    locations."/assets/".extraConfig = ''
      add_header Cache-Control "public, max-age=86400";
    '';
  };
}
