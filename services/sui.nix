{
  config,
  lib,
  pkgs,
  ...
}: let
  domain = "start.adnanshaikh.com";

  # Weekly Kagi Search API v1 refresh. Encrypt the key from
  # https://kagi.com/api/keys as secrets/kagi-api-token (`sops -e -i`).
  kagiTokenFile = ./../secrets/kagi-api-token;
  hasKagiToken = builtins.pathExists kagiTokenFile;

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
        name = "Beancount";
        url = "beancount.adnanshaikh.com";
        icon = "calculator-variant";
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
            name = "Beancount";
            url = "https://beancount.adnanshaikh.com";
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

  providersJson = pkgs.writeText "providers.json" (builtins.toJSON {
    providers = [
      {
        name = "Kagi";
        url = "https://kagi.com/search?q=";
        prefix = "/k";
      }
      {
        name = "YouTube";
        url = "https://www.youtube.com/results?search_query=";
        prefix = "/y";
      }
      {
        name = "TheMovieDB";
        url = "https://www.themoviedb.org/search?query=";
        prefix = "/m";
      }
      {
        name = "TheTVDB";
        url = "https://www.thetvdb.com/search?query=";
        prefix = "/tv";
      }
      {
        name = "iMDB";
        url = "https://www.imdb.com/find?q=";
        prefix = "/i";
      }
      {
        name = "Duck Duck Go";
        url = "https://duckduckgo.com/?q=";
        prefix = "/d";
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

    table,
    table td,
    table th {
      border-color: #333333;
      color: #f2f2f2;
    }

    table a {
      color: #f2f2f2;
    }

    .theme-black {
      background-color: #000000;
      border: 4px solid #6e6e6e;
      color: #f2f2f2;
    }

    #good-news {
      padding-bottom: 6vh;
    }

    #good-news h3 {
      height: auto;
      margin-bottom: 0.55em;
    }

    .good-news-meta {
      color: var(--color-text-acc);
      font-size: 0.8em;
      margin: 0 0 0.55em 0;
      text-transform: uppercase;
    }

    .good-news-lede {
      color: var(--color-text-acc);
      font-size: 0.9em;
      line-height: 1.4;
      margin: 0 0 2.6em 0;
    }

    #good-news-items {
      display: grid;
      grid-column-gap: 2.5em;
      grid-row-gap: 1.6em;
      grid-template-columns: 1fr 1fr;
    }

    .good-news-item h4 {
      font-size: 1em;
      font-weight: 500;
      height: auto;
      line-height: 1.35;
      margin: 0 0 0.35em 0;
      text-transform: none;
    }

    .good-news-item h4 a {
      color: var(--color-text-pri);
    }

    .good-news-item p {
      color: var(--color-text-acc);
      display: -webkit-box;
      font-size: 0.9em;
      -webkit-box-orient: vertical;
      -webkit-line-clamp: 3;
      line-height: 1.45;
      margin: 0 0 0.45em 0;
      overflow: hidden;
    }

    .good-news-item .good-news-source {
      color: var(--color-text-acc);
      font-size: 0.75em;
      letter-spacing: 0.04em;
      text-transform: uppercase;
    }

    @media screen and (max-width: 667px) {
      #good-news-items {
        grid-template-columns: 1fr;
      }
    }
  '';

  patchSui = pkgs.writeText "patch-sui.py" ''
    import sys
    from pathlib import Path

    root = Path(sys.argv[1])

    html = (root / "index.html").read_text()
    html = html.replace("<title>SUI</title>", "<title>shaikhlab</title>")
    html = html.replace(
        'href="./assets/css/styles.css"',
        'href="./assets/css/styles.css">\n    <link type="text/css" rel="stylesheet" href="./assets/css/shaikhlab.css"',
    )
    html = html.replace('href="http://{{url}}"', 'href="https://{{url}}"')
    html = html.replace(
        '<button data-theme="blackboard"',
        '<button data-theme="black" class="theme-button theme-black">Black</button>\n                <button data-theme="blackboard"',
    )
    if "</main>" not in html:
        raise SystemExit("index.html </main> not found")
    html = html.replace(
        "</main>",
        """<section id="good-news">
            <h3>Good news</h3>
            <p class="good-news-meta" id="good-news-meta"></p>
            <p class="good-news-lede" id="good-news-lede"></p>
            <div id="good-news-items"></div>
        </section>
    </main>""",
        1,
    )
    html = html.replace(
        '<script src="./assets/js/search.js" type="text/javascript"></script>',
        '<script src="./assets/js/search.js" type="text/javascript"></script>\n    <script src="./assets/js/good-news.js" type="text/javascript"></script>',
    )
    (root / "index.html").write_text(html)

    search = (root / "assets/js/search.js").read_text()
    # New tabs keep address-bar focus; don't steal it with the in-page search box.
    old_search_focus = "document.getElementById('keywords').focus();"
    if old_search_focus not in search:
        raise SystemExit("search.js keywords focus() not found")
    search = search.replace(old_search_focus, "", 1)
    search = search.replace(
        'var sengine = "https://www.google.com/?q=";',
        'var sengine = "https://kagi.com/search?q=";',
    )
    search = search.replace(
        'case "am":',
        'case "k":\n                    window.location = "https://kagi.com/search?q=" + subtext;\n                    break;\n                case "am":',
    )
    (root / "assets/js/search.js").write_text(search)

    themer = (root / "assets/js/themer.js").read_text()
    themer = themer.replace(
        "case 'blackboard':",
        """case 'black':
            setTheme({
                'color-background': '#000000',
                'color-text-pri': '#f2f2f2',
                'color-text-acc': '#6e6e6e'
            });
            return;

        case 'blackboard':""",
    )
    old_theme_init = (
        "setValueFromLocalStorage('color-background');\n"
        "    setValueFromLocalStorage('color-text-pri');\n"
        "    setValueFromLocalStorage('color-text-acc');"
    )
    new_theme_init = (
        "if (!localStorage.getItem('color-background')) {\n"
        "        setTheme({\n"
        "            'color-background': '#000000',\n"
        "            'color-text-pri': '#f2f2f2',\n"
        "            'color-text-acc': '#6e6e6e'\n"
        "        });\n"
        "    } else {\n"
        "        setValueFromLocalStorage('color-background');\n"
        "        setValueFromLocalStorage('color-text-pri');\n"
        "        setValueFromLocalStorage('color-text-acc');\n"
        "    }"
    )
    if old_theme_init not in themer:
        raise SystemExit("themer.js theme init block not found")
    themer = themer.replace(old_theme_init, new_theme_init)
    (root / "assets/js/themer.js").write_text(themer)

    html = (root / "index.html").read_text()
    search = (root / "assets/js/search.js").read_text()
    themer = (root / "assets/js/themer.js").read_text()
    assert "shaikhlab" in html
    assert "https://{{url}}" in html
    assert "data-theme=\"black\"" in html
    assert "shaikhlab.css" in html
    assert 'id="good-news"' in html
    assert "good-news.js" in html
    assert "kagi.com/search" in search
    assert "case \"k\":" in search
    assert "document.getElementById('keywords').focus();" not in search
    assert "case 'black':" in themer
    assert "localStorage.getItem('color-background')" in themer
  '';

  suiRoot = pkgs.runCommand "sui-shaikhlab" {nativeBuildInputs = [pkgs.python3];} ''
    mkdir -p $out
    cp -r ${suiSrc}/. $out/
    chmod -R u+w $out

    cp ${appsJson} $out/apps.json
    cp ${linksJson} $out/links.json
    cp ${providersJson} $out/providers.json
    cp ${extraCss} $out/assets/css/shaikhlab.css
    cp ${./sui/good-news.js} $out/assets/js/good-news.js
    cp ${./sui/good-news.fallback.json} $out/good-news.fallback.json

    python3 ${patchSui} $out
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
    '';
    locations."= /good-news.json" = {
      alias = "/var/lib/sui-good-news/news.json";
      extraConfig = ''
        default_type application/json;
        add_header Cache-Control "public, max-age=300";
      '';
    };
  };

  environment.persistence."/nix/persist".directories = [
    "/var/lib/sui-good-news"
  ];

  sops.secrets = lib.mkIf hasKagiToken {
    "kagi-api-token" = {
      format = "binary";
      sopsFile = kagiTokenFile;
      mode = "0400";
    };
  };

  systemd.services.sui-good-news = lib.mkIf hasKagiToken {
    description = "Refresh startpage good-news digest via Kagi Search API v1";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    path = [pkgs.python3];

    serviceConfig = {
      Type = "oneshot";
      User = "nginx";
      Group = "nginx";
      StateDirectory = "sui-good-news";
      StateDirectoryMode = "0755";
      WorkingDirectory = "/var/lib/sui-good-news";
      LoadCredential = "kagi-api-token:${config.sops.secrets."kagi-api-token".path}";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };

    script = ''
      set -eu
      python3 ${./sui/fetch-good-news.py} \
        --token-file "$CREDENTIALS_DIRECTORY/kagi-api-token" \
        --output /var/lib/sui-good-news/news.json
    '';
  };

  systemd.timers.sui-good-news = lib.mkIf hasKagiToken {
    description = "Weekly startpage good-news refresh";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "Sun *-*-* 07:00:00";
      OnBootSec = "3min";
      Persistent = true;
      Unit = "sui-good-news.service";
    };
  };
}
