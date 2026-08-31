#!/usr/bin/env python3
"""Refresh the startpage good-news digest via Kagi Search API v1.

v1 exposes search and extract (not FastGPT). Several targeted US queries
are run with a last-30-days filter, then titles and snippets are turned
into a digest. A failed run leaves the previous file in place.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta, timezone

SEARCH_URL = "https://kagi.com/api/v1/search"
EXTRACT_URL = "https://kagi.com/api/v1/extract"
WINDOW_DAYS = 30
MAX_ITEMS = 8
PER_QUERY_LIMIT = 8

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


def extract_pages(token: str, urls: list[str]) -> dict[str, str]:
    if not urls:
        return {}
    pages = [{"url": url} for url in urls[:10]]
    try:
        raw = request_json(
            EXTRACT_URL,
            token,
            {"pages": pages, "timeout": 20},
            timeout=60,
        )
    except SystemExit as err:
        print(f"extract skipped: {err}", file=sys.stderr)
        return {}

    found: dict[str, str] = {}
    data = raw.get("data") or raw
    candidates = []
    if isinstance(data, list):
        candidates = data
    elif isinstance(data, dict):
        for key in ("pages", "results", "extract"):
            value = data.get(key)
            if isinstance(value, list):
                candidates = value
                break
        if not candidates:
            candidates = [data]

    for item in candidates:
        if not isinstance(item, dict):
            continue
        url = str(item.get("url") or item.get("requested_url") or "").strip()
        markdown = str(
            item.get("markdown")
            or item.get("content")
            or item.get("text")
            or item.get("output")
            or ""
        ).strip()
        if url and markdown:
            found[url] = markdown
    return found


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
    host = host_of(url).lower().removeprefix("www.")
    if any(host == skip or host.endswith("." + skip) for skip in SKIP_HOSTS):
        return False
    blob = f"{title} {snippet}".lower()
    if any(word in blob for word in SKIP_WORDS):
        return False
    return True


def score_result(title: str, snippet: str) -> int:
    blob = f"{title} {snippet}".lower()
    score = sum(1 for word in POSITIVE_WORDS if word in blob)
    if "2026" in blob:
        score += 2
    return score


def first_sentences(text: str, limit: int = 2) -> str:
    cleaned = re.sub(r"```.*?```", " ", text, flags=re.S)
    cleaned = re.sub(r"[#*_>`]+", " ", cleaned)
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    if not cleaned:
        return ""
    parts = re.split(r"(?<=[.!?])\s+", cleaned)
    return " ".join(parts[:limit]).strip()


def collect(token: str, start: date, end: date) -> list[dict]:
    seen: set[str] = set()
    collected: list[dict] = []

    for query in QUERIES:
        raw = search(token, query, start, end)
        if raw.get("error"):
            print(f"search warning for {query!r}: {raw['error']}", file=sys.stderr)
        for item in iter_result_buckets(raw.get("data") or {}):
            title = str(item.get("title") or "").strip()
            url = str(item.get("url") or "").strip()
            snippet = str(item.get("snippet") or "").strip()
            if url in seen or not keep_result(title, snippet, url):
                continue
            seen.add(url)
            collected.append(
                {
                    "headline": title,
                    "summary": snippet,
                    "date": normalize_time(str(item.get("time") or "")),
                    "source_title": host_of(url).removeprefix("www.") or url,
                    "source_url": url,
                    "_score": score_result(title, snippet),
                }
            )

    collected.sort(key=lambda item: item["_score"], reverse=True)
    return collected[:MAX_ITEMS]


def enrich_summaries(token: str, items: list[dict]) -> None:
    extracted = extract_pages(token, [item["source_url"] for item in items])
    if not extracted:
        return
    for item in items:
        markdown = extracted.get(item["source_url"])
        if not markdown:
            continue
        sentences = first_sentences(markdown, 3)
        if len(sentences) > len(item["summary"]):
            item["summary"] = sentences


def digest_from_items(items: list[dict], start: date, end: date) -> dict:
    if not items:
        raise SystemExit("Kagi search returned no usable stories")

    cleaned = []
    for item in items:
        row = {k: v for k, v in item.items() if not k.startswith("_")}
        if not row["summary"]:
            row["summary"] = row["headline"]
        cleaned.append(row)

    heads = [item["headline"] for item in cleaned[:3]]
    lede = f"{len(cleaned)} constructive US stories from the last month"
    if heads:
        lede += f", including {heads[0].rstrip('.')}"
        if len(heads) > 1:
            lede += f" and {heads[1].rstrip('.')}"
        lede += "."

    return {
        "updated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "window_start": start.isoformat(),
        "window_end": end.isoformat(),
        "lede": lede,
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
    enrich_summaries(token, items)
    digest = digest_from_items(items, start, end)

    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    write_atomic(args.output, digest)
    print(f"wrote {len(digest['items'])} items to {args.output}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
