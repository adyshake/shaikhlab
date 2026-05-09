/**
 * PAC for blocking distracting sites (Apple Configurator / iOS supervised profiles).
 *
 * Profile: Wi‑Fi or Global HTTP Proxy → Automatic → PAC URL pointing at the raw GitHub URL of this file.
 * Traffic for listed hosts is sent to 127.0.0.1:9999 (no listener → connection fails / timeout).
 *
 * Intentionally omits gateway.icloud.com and Apple News client hosts — those interfere with core
 * iCloud and system features (Photos, backups, Stocks/Spotlight news, widgets).
 */

function FindProxyForURL(url, host) {
    var blocked = [
        // --- Forums & aggregators (dnsDomainIs catches subdomains) ---
        "reddit.com",
        "news.ycombinator.com",
        "hn.algolia.com",
        "hckrnws.com",
        "hackerweb.app",
        "hackerwebapp.com",
        "lobste.rs",
        "hn.etelej.com",

        // --- Social & short video ---
        "facebook.com",
        "fb.com",
        "instagram.com",
        "twitter.com",
        "x.com",
        "tiktok.com",
        "twitch.tv",

        // --- News: US broadcast & cable ---
        "cnn.com",
        "foxnews.com",
        "msnbc.com",
        "nbcnews.com",
        "cbsnews.com",
        "abcnews.go.com",
        "msn.com",

        // --- News: newspapers & wires ---
        "nytimes.com",
        "wsj.com",
        "washingtonpost.com",
        "usatoday.com",
        "latimes.com",
        "bostonglobe.com",
        "chicagotribune.com",
        "miamiherald.com",
        "denverpost.com",
        "seattletimes.com",
        "inquirer.com",
        "nj.com",
        "reuters.com",
        "apnews.com",
        "bloomberg.com",
        "ft.com",
        "politico.com",
        "thehill.com",
        "axios.com",

        // --- News: national magazines & digital-native ---
        "time.com",
        "theatlantic.com",
        "economist.com",
        "foreignpolicy.com",
        "nationalreview.com",
        "thedailybeast.com",
        "salon.com",
        "slate.com",
        "vox.com",
        "businessinsider.com",
        "huffpost.com",
        "buzzfeed.com",

        // --- News: UK & international ---
        "bbc.com",
        "bbc.co.uk",
        "theguardian.com",
        "guardian.co.uk",
        "telegraph.co.uk",
        "dailymail.co.uk",
        "mirror.co.uk",
        "thetimes.co.uk",
        "news.sky.com",

        // --- News: public / global ---
        "npr.org",
        "dw.com",
        "aljazeera.com",

        // --- News: aggregators & in-app portals ---
        "news.yahoo.com",
        "news.google.com"
    ];

    for (var i = 0; i < blocked.length; i++) {
        if (dnsDomainIs(host, blocked[i]) || host === blocked[i]) {
            return "PROXY 127.0.0.1:9999";
        }
    }

    return "DIRECT";
}
