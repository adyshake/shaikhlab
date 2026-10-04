#!/usr/bin/env python3
"""Bake the start page so a new tab does not wait on third parties.

Apps and bookmarks are written into index.html. Icons are inline SVGs
(Pictogrammers MDI, Apache-2.0). Google Fonts, Handlebars, Iconify,
the search box, and the entrance fade are removed.
"""

import html
import json
import re
import sys
from pathlib import Path


def load_icons(path: Path) -> dict[str, str]:
    data = json.loads(path.read_text())
    icons = data["icons"]
    if data.get("width") != 24 or data.get("height") != 24:
        raise SystemExit("icons.json is not a 24px set")
    return icons


def svg(icons: dict[str, str], name: str, *, large: bool) -> str:
    try:
        body = icons[name]
    except KeyError:
        raise SystemExit(f"missing icon {name}") from None
    if "<script" in body or "href=" in body:
        raise SystemExit(f"refusing icon {name}")
    cls = ' class="icon"' if large else ""
    return (
        f'<svg{cls} xmlns="http://www.w3.org/2000/svg" width="1em" height="1em" '
        f'viewBox="0 0 24 24" aria-hidden="true" focusable="false">{body}</svg>'
    )


def render_apps(icons: dict[str, str], data: dict) -> str:
    rows = []
    for app in data["apps"]:
        name = html.escape(app["name"])
        url = html.escape(app["url"], quote=True)
        target = ""
        if app.get("target"):
            target = f' target="{html.escape(app["target"], quote=True)}"'
        rows.append(
            "                <div class=\"apps_item\">\n"
            "                    <div class=\"apps_icon\">\n"
            f"                        {svg(icons, app['icon'], large=True)}\n"
            "                    </div>\n"
            "                    <div class=\"apps_text\">\n"
            f"                        <a href=\"https://{url}\"{target}>{name}</a>\n"
            f"                        <span id=\"app-address\">{html.escape(app['url'])}</span>\n"
            "                    </div>\n"
            "                </div>"
        )
    body = "\n".join(rows)
    return (
        "            <h3>Applications</h3>\n"
        "            <div id=\"apps_loop\">\n"
        f"{body}\n"
        "            </div>"
    )


def render_links(data: dict) -> str:
    blocks = []
    for group in data["bookmarks"]:
        links = []
        for link in group["links"]:
            name = html.escape(link["name"])
            url = html.escape(link["url"], quote=True)
            target = ""
            if link.get("target"):
                target = f' target="{html.escape(link["target"], quote=True)}"'
            links.append(
                f'                        <a href="{url}"{target} '
                f'class="theme_color-border theme_text-select">{name}</a>'
            )
        joined = "\n".join(links)
        blocks.append(
            "                    <div id=\"links_item\">\n"
            f"                        <h4>{html.escape(group['category'])}</h4>\n"
            f"{joined}\n"
            "                    </div>"
        )
    body = "\n".join(blocks)
    return (
        "            <h3>Bookmarks</h3>\n"
        "            <div id=\"links_loop\">\n"
        f"{body}\n"
        "            </div>"
    )


def replace_section(page: str, section_id: str, inner: str) -> str:
    pattern = rf'(<section id="{section_id}">).*?(</section>)'
    updated, count = re.subn(pattern, rf"\1\n{inner}\n        \2", page, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"section {section_id} not found")
    return updated


def replace_icon_spans(page: str, icons: dict[str, str]) -> str:
    pattern = re.compile(r'<span class="([^"]*)" data-icon="mdi-([^"]+)"></span>')

    def repl(match: re.Match) -> str:
        classes = match.group(1).split()
        return svg(icons, match.group(2), large="icon" in classes)

    updated, count = pattern.subn(repl, page)
    if count < 1:
        raise SystemExit("iconify spans not found")
    if "data-icon=" in updated or "iconify" in updated:
        raise SystemExit("iconify markup remains")
    return updated


def strip_fade(css: str) -> str:
    start = css.find("/* ANIMATION */")
    end = css.find("/* LAYOUT */")
    if start < 0 or end < 0 or end < start:
        raise SystemExit("fade css block not found")
    return css[:start] + css[end:]


def remove_block(page: str, pattern: str, label: str) -> str:
    updated, count = re.subn(pattern, "\n", page, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"{label} not found")
    return updated


def main() -> None:
    root = Path(sys.argv[1])
    apps = json.loads(Path(sys.argv[2]).read_text())
    links = json.loads(Path(sys.argv[3]).read_text())
    icons = load_icons(Path(sys.argv[4]))

    page = (root / "index.html").read_text()
    page = page.replace("<title>SUI</title>", "<title>shaikhlab</title>")
    page = page.replace(
        'href="./assets/css/styles.css"',
        'href="./assets/css/styles.css">\n    <link type="text/css" rel="stylesheet" href="./assets/css/shaikhlab.css"',
    )
    page = page.replace(
        '<button data-theme="blackboard"',
        '<button data-theme="black" class="theme-button theme-black">Black</button>\n                <button data-theme="blackboard"',
    )
    for snippet in (
        '    <link href="https://fonts.googleapis.com/css?family=Roboto:400,500,700,900" rel="stylesheet">\n',
        '    <script src="https://cdnjs.cloudflare.com/ajax/libs/handlebars.js/4.7.7/handlebars.min.js"></script>\n',
        '    <script src="https://code.iconify.design/1/1.0.7/iconify.min.js"></script>\n',
        '    <script src="./assets/js/data.js" type="text/javascript"></script>\n',
    ):
        if snippet not in page:
            raise SystemExit(f"missing snippet: {snippet.strip()}")
        page = page.replace(snippet, "")
    page = page.replace('<main id="container" class="fade">', '<main id="container">')
    page = remove_block(
        page,
        r'\s*<section id="search">.*?</section>',
        "search box",
    )
    page = remove_block(
        page,
        r'\s*<h2>Search options</h2>\s*<section id="providers">.*?</section>',
        "search options",
    )
    search_script = '    <script src="./assets/js/search.js" type="text/javascript"></script>\n'
    if search_script not in page:
        raise SystemExit("search.js script tag not found")
    page = page.replace(search_script, "")
    page = replace_section(page, "apps", render_apps(icons, apps))
    page = replace_section(page, "links", render_links(links))
    page = replace_icon_spans(page, icons)
    (root / "index.html").write_text(page)

    css = (root / "assets/css/styles.css").read_text()
    css = strip_fade(css)
    (root / "assets/css/styles.css").write_text(css)

    for unused in ("data.js", "search.js"):
        path = root / "assets/js" / unused
        if path.exists():
            path.unlink()

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

    page = (root / "index.html").read_text()
    themer = (root / "assets/js/themer.js").read_text()
    css = (root / "assets/css/styles.css").read_text()
    assert "shaikhlab" in page
    assert "shaikhlab.css" in page
    assert 'data-theme="black"' in page
    assert "https://watch.adnanshaikh.com" in page
    assert "https://assistant.kagi.com" in page
    assert "<svg" in page
    assert "{{" not in page
    assert "fonts.googleapis.com" not in page
    assert "handlebars" not in page
    assert "iconify" not in page
    assert "data.js" not in page
    assert "search.js" not in page
    assert 'id="keywords"' not in page
    assert 'id="search"' not in page
    assert "Search options" not in page
    assert 'class="fade"' not in page
    assert 'id="good-news"' not in page
    assert "fadeseq" not in css
    assert not (root / "assets/js/search.js").exists()
    assert "case 'black':" in themer
    assert "localStorage.getItem('color-background')" in themer


if __name__ == "__main__":
    main()
