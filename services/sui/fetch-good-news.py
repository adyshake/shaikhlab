#!/usr/bin/env python3
"""Refresh the startpage good-news digest via Kagi Search API v1.

Several targeted US queries run with a last-30-days filter. Search
snippets are cleaned into short cards. A failed run leaves the previous
file in place.
"""

from __future__ import annotations

import argparse
import html
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta, timezone

SEARCH_URL = "https://kagi.com/api/v1/search"
WINDOW_DAYS = 30
MAX_ITEMS = 8
PER_QUERY_LIMIT = 8
SUMMARY_CHARS = 220

QUERIES = (
    "2026 United States infrastructure upgrade transit water housing announced",
    "2026 US climate resilience flood protection project funded",
    "2026 United States housing climate energy law passed",
    "2026 US infrastructure investment capital grid manufacturing",
)

SKIP_HOSTS = (
    "youtube.com",
    "youtu.be",
    "tiktok.com",
    "facebook.com",
    "instagram.com",
    "x.com",
    "twitter.com",
    "reddit.com",
)

SKIP_SUFFIXES = (".pdf", ".doc", ".docx", ".ppt", ".pptx", ".xls", ".xlsx")

JUNK_MARKERS = (
    "pdfformatversion",
    "islinearized",
    "isacroformpresent",
    "xmp:modifydate",
    "facebook.com/sharer",
    "twitter.com/intent",
    "linkedin.com/share",
    "reddit.com/submit",
)

SKIP_WORDS = (
    "box office",
    "stock price",
    "closes at",
    "dies at",
    "killed",
    "massacre",
    "celebrity",
    "box-office",
)

POSITIVE_WORDS = (
    "infrastructure",
    "climate",
    "resilien",
    "housing",
    "transit",
    "grid",
    "flood",
    "solar",
    "wind",
    "investment",
    "funding",
    "grant",
    "law",
    "enact",
    "upgrade",
    "rebuild",
    "broadband",
    "water",
    "rail",
    "transmission",
)


def window(today: date) -> tuple[date, date]:
    return today - timedelta(days=WINDOW_DAYS), today


def host_of(url: str) -> str:
    try:
        return urllib.parse.urlparse(url).hostname or ""
    except ValueError:
        return ""


def normalize_time(value: str) -> str:
    value = (value or "").strip()
    if not value:
        return ""
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        return value
    match = re.match(r"(\d{4}-\d{2}-\d{2})", value)
    return match.group(1) if match else ""


def request_json(url: str, token: str, body: dict, timeout: int) -> dict:
    payload = json.dumps(body).encode()
    req = urllib.request.Request(
        url,
        data=payload,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as err:
        detail = err.read().decode(errors="replace")
        raise SystemExit(f"Kagi {url} HTTP {err.code}: {detail}") from err
    except urllib.error.URLError as err:
        raise SystemExit(f"Kagi request failed: {err}") from err


def search(token: str, query: str, start: date, end: date) -> dict:
    return request_json(
        SEARCH_URL,
        token,
        {
            "query": query,
            "limit": PER_QUERY_LIMIT,
            "filters": {
                "region": "us",
                "after": start.isoformat(),
                "before": end.isoformat(),
            },
        },
        timeout=45,
    )


def clean_text(text: str) -> str:
    cleaned = html.unescape(text or "")
    cleaned = re.sub(r"(?is)<script\b.*?</script>", " ", cleaned)
    cleaned = re.sub(r"(?is)<style\b.*?</style>", " ", cleaned)
    cleaned = re.sub(r"!\[.*?\]\(.*?\)", " ", cleaned)
    cleaned = re.sub(r"\[([^\]]*)\]\([^)]+\)", r"\1", cleaned)
    cleaned = re.sub(r"<[^>]+>", " ", cleaned)
    cleaned = re.sub(r"https?://\S+", " ", cleaned)
    cleaned = re.sub(r"[#*_>`|]+", " ", cleaned)
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    if any(marker in cleaned.lower() for marker in JUNK_MARKERS):
        return ""
    return cleaned


def clip_summary(text: str) -> str:
    cleaned = clean_text(text)
    if not cleaned:
        return ""
    parts = re.split(r"(?<=[.!?])\s+", cleaned)
    clipped = " ".join(parts[:2]).strip()
    if len(clipped) > SUMMARY_CHARS:
        clipped = clipped[: SUMMARY_CHARS - 1].rsplit(" ", 1)[0].rstrip(".,;:") + "…"
    return clipped


def clean_headline(title: str) -> str:
    title = clean_text(title)
    title = re.sub(r"\s+\.\.\.$", "", title)
    title = re.sub(r"\s+…$", "", title)
    return title


def story_key(title: str) -> str:
    words = re.sub(r"[^a-z0-9]+", " ", title.lower()).split()
    return " ".join(words[:6])


def is_homepage(url: str) -> bool:
    parsed = urllib.parse.urlparse(url)
    return parsed.path in ("", "/") and not parsed.query


def iter_result_buckets(data: dict) -> list[dict]:
    items: list[dict] = []
    if not isinstance(data, dict):
        return items
    for key in ("news", "interesting_news", "search", "interesting_finds"):
        bucket = data.get(key) or []
        if not isinstance(bucket, list):
            continue
        for raw in bucket:
            if isinstance(raw, dict):
                items.append(raw)
    return items


def keep_result(title: str, snippet: str, url: str) -> bool:
    if not title or not url.startswith("http"):
        return False
    parsed = urllib.parse.urlparse(url)
    host = (parsed.hostname or "").lower().removeprefix("www.")
    path = (parsed.path or "").lower()
    if any(host == skip or host.endswith("." + skip) for skip in SKIP_HOSTS):
        return False
    if any(path.endswith(suffix) for suffix in SKIP_SUFFIXES):
        return False
    if is_homepage(url):
        return False
    blob = f"{title} {snippet}".lower()
    if any(word in blob for word in SKIP_WORDS):
        return False
    if any(marker in blob for marker in JUNK_MARKERS):
        return False
    return True


def score_result(title: str, snippet: str) -> int:
    blob = f"{title} {snippet}".lower()
    score = sum(1 for word in POSITIVE_WORDS if word in blob)
    if "2026" in blob:
        score += 2
    return score


def collect(token: str, start: date, end: date) -> list[dict]:
    seen_urls: set[str] = set()
    seen_stories: set[str] = set()
    collected: list[dict] = []

    for query in QUERIES:
        raw = search(token, query, start, end)
        if raw.get("error"):
            print(f"search warning for {query!r}: {raw['error']}", file=sys.stderr)
        for item in iter_result_buckets(raw.get("data") or {}):
            url = str(item.get("url") or "").strip()
            headline = clean_headline(str(item.get("title") or ""))
            summary = clip_summary(str(item.get("snippet") or ""))
            if url in seen_urls or not keep_result(headline, summary, url):
                continue
            if not summary:
                continue
            key = story_key(headline)
            if key in seen_stories:
                continue
            seen_urls.add(url)
            seen_stories.add(key)
            collected.append(
                {
                    "headline": headline,
                    "summary": summary,
                    "date": normalize_time(str(item.get("time") or "")),
                    "source_title": host_of(url).removeprefix("www.") or url,
                    "source_url": url,
                    "_score": score_result(headline, summary),
                }
            )

    collected.sort(key=lambda item: item["_score"], reverse=True)
    return collected[:MAX_ITEMS]


def digest_from_items(items: list[dict], start: date, end: date) -> dict:
    if not items:
        raise SystemExit("Kagi search returned no usable stories")

    cleaned = [{k: v for k, v in item.items() if not k.startswith("_")} for item in items]

    return {
        "updated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "window_start": start.isoformat(),
        "window_end": end.isoformat(),
        "lede": "Infrastructure, climate, housing, and investment.",
        "items": cleaned,
        "references": [
            {"title": item["source_title"], "url": item["source_url"]}
            for item in cleaned
        ],
        "source": "kagi-search-v1",
    }


def write_atomic(path: str, payload: dict) -> None:
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    os.replace(tmp, path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--token-file",
        default=os.environ.get("KAGI_TOKEN_FILE", ""),
        help="file containing the Kagi API v1 key",
    )
    parser.add_argument(
        "--output",
        default=os.path.join(os.environ.get("STATE_DIRECTORY", "."), "news.json"),
        help="destination JSON path",
    )
    args = parser.parse_args()

    if not args.token_file:
        print("missing --token-file / KAGI_TOKEN_FILE", file=sys.stderr)
        return 2
    token = open(args.token_file, encoding="utf-8").read().strip()
    if not token:
        print("Kagi token file is empty", file=sys.stderr)
        return 2

    today = datetime.now(timezone.utc).date()
    start, end = window(today)
    items = collect(token, start, end)
    digest = digest_from_items(items, start, end)

    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    write_atomic(args.output, digest)
    print(f"wrote {len(digest['items'])} items to {args.output}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
