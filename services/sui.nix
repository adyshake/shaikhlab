{pkgs, ...}: let
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
    (root / "index.html").write_text(html)

    search = (root / "assets/js/search.js").read_text()
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
    assert "kagi.com/search" in search
    assert "case \"k\":" in search
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
  };
}
