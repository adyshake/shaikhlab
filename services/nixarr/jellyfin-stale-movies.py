#!/usr/bin/env python3
"""Delete movies that have sat at 'watched' in Jellyfin for a week.

A title counts as watched if Jellyfin marked it Played, or playback is
at least WATCHED_PCT of runtime (default 85). LastPlayedDate must be
at least STALE_DAYS old. Favorites and a `keep` tag (Jellyfin or
Radarr) are left alone. Delete goes through Radarr (files + movie,
list-exclusion on) so it does not get grabbed again. Movies only in
Jellyfin are deleted via its API.
"""

from __future__ import annotations

import json
import os
import shutil
import sqlite3
import sys
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone
from typing import Any

WATCHED_PCT = float(os.environ.get("WATCHED_PCT", "0.85"))
STALE_DAYS = int(os.environ.get("STALE_DAYS", "7"))
DRY_RUN = os.environ.get("DRY_RUN", "") in ("1", "true", "yes")
JELLYFIN_DB = os.environ.get(
    "JELLYFIN_DB", "/var/lib/nixarr/jellyfin/data/data/jellyfin.db"
)
RADARR_CONFIG = os.environ.get(
    "RADARR_CONFIG", "/var/lib/nixarr/radarr/config.xml"
)
JELLYFIN_URL = os.environ.get("JELLYFIN_URL", "http://127.0.0.1:8096").rstrip("/")
RADARR_URL = os.environ.get("RADARR_URL", "http://127.0.0.1:7878").rstrip("/")
MOVIES_DIR = os.path.realpath(
    os.environ.get("MOVIES_DIR", "/data/fun/library/movies")
)
MOVIE_TYPE = "MediaBrowser.Controller.Entities.Movies.Movie"


def log(msg: str) -> None:
    print(msg, flush=True)


def parse_jf_dt(raw: str | None) -> datetime | None:
    if not raw:
        return None
    text = raw.replace("T", " ").strip()
    if "." in text:
        head, frac = text.split(".", 1)
        digits = "".join(c for c in frac if c.isdigit())[:6].ljust(6, "0")
        text = f"{head}.{digits}"
    try:
        dt = datetime.fromisoformat(text)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def has_keep_tag(tags: str | None) -> bool:
    if not tags:
        return False
    parts = [p.strip().lower() for p in tags.replace("|", ",").split(",")]
    return "keep" in parts


def xml_text(path: str, tag: str) -> str:
    root = ET.parse(path).getroot()
    node = root.find(tag)
    if node is None or not node.text:
        raise RuntimeError(f"{tag} missing from {path}")
    return node.text.strip()


def http_json(
    method: str,
    url: str,
    headers: dict[str, str],
    body: dict[str, Any] | None = None,
) -> Any:
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    if body is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read()
            if not raw:
                return None
            return json.loads(raw)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")
        raise RuntimeError(f"{method} {url} -> {exc.code}: {detail}") from exc


def stale_movies(db: sqlite3.Connection, cutoff: datetime) -> list[dict[str, Any]]:
    db.row_factory = sqlite3.Row
    rows = db.execute(
        """
        SELECT
          b.Id AS item_id,
          b.Name AS name,
          b.ProductionYear AS year,
          b.Path AS path,
          b.Tags AS tags,
          b.RunTimeTicks AS runtime_ticks,
          u.UserId AS user_id,
          MAX(u.Played) AS played,
          MAX(u.IsFavorite) AS favorite,
          MAX(u.PlaybackPositionTicks) AS position_ticks,
          MAX(u.LastPlayedDate) AS last_played
        FROM BaseItems b
        JOIN UserData u ON u.ItemId = b.Id
        WHERE b.Type = ?
          AND b.IsVirtualItem = 0
        GROUP BY b.Id, u.UserId
        """,
        (MOVIE_TYPE,),
    ).fetchall()

    providers: dict[str, dict[str, str]] = {}
    for row in db.execute(
        """
        SELECT p.ItemId, p.ProviderId, p.ProviderValue
        FROM BaseItemProviders p
        JOIN BaseItems b ON b.Id = p.ItemId
        WHERE b.Type = ?
        """,
        (MOVIE_TYPE,),
    ):
        providers.setdefault(row[0], {})[row[1]] = row[2]

    by_item: dict[str, list[sqlite3.Row]] = {}
    for row in rows:
        by_item.setdefault(row["item_id"], []).append(row)

    stale: list[dict[str, Any]] = []
    for item_id, user_rows in by_item.items():
        if any(r["favorite"] for r in user_rows):
            continue
        if has_keep_tag(user_rows[0]["tags"]):
            continue

        last_dates = [parse_jf_dt(r["last_played"]) for r in user_rows]
        last_dates = [d for d in last_dates if d is not None]
        if not last_dates:
            continue
        last_played = max(last_dates)
        if last_played > cutoff:
            continue

        runtime = user_rows[0]["runtime_ticks"] or 0
        watched = False
        in_progress = False
        best_pct = 0.0
        for r in user_rows:
            pos = r["position_ticks"] or 0
            pct = (pos / runtime) if runtime else 0.0
            best_pct = max(best_pct, pct)
            if r["played"] or pct >= WATCHED_PCT:
                watched = True
            elif 0 < pct < WATCHED_PCT:
                in_progress = True
        if in_progress or not watched:
            continue

        ids = providers.get(item_id, {})
        stale.append(
            {
                "item_id": item_id,
                "name": user_rows[0]["name"],
                "year": user_rows[0]["year"],
                "path": user_rows[0]["path"],
                "pct": best_pct,
                "played": any(bool(r["played"]) for r in user_rows),
                "last_played": last_played,
                "tmdb": ids.get("Tmdb"),
                "imdb": ids.get("Imdb"),
            }
        )
    stale.sort(key=lambda m: (m["last_played"], m["name"] or ""))
    return stale


def radarr_index(api_key: str) -> tuple[dict[int, dict[str, Any]], dict[str, dict[str, Any]]]:
    headers = {"X-Api-Key": api_key}
    movies = http_json("GET", f"{RADARR_URL}/api/v3/movie", headers) or []
    by_tmdb: dict[int, dict[str, Any]] = {}
    by_imdb: dict[str, dict[str, Any]] = {}
    for movie in movies:
        tmdb = movie.get("tmdbId")
        if tmdb:
            by_tmdb[int(tmdb)] = movie
        imdb = movie.get("imdbId")
        if imdb:
            by_imdb[str(imdb)] = movie
    return by_tmdb, by_imdb


def radarr_keep_ids(api_key: str) -> set[int]:
    headers = {"X-Api-Key": api_key}
    tags = http_json("GET", f"{RADARR_URL}/api/v3/tag", headers) or []
    return {int(t["id"]) for t in tags if str(t.get("label", "")).lower() == "keep"}


def match_radarr(
    movie: dict[str, Any],
    by_tmdb: dict[int, dict[str, Any]],
    by_imdb: dict[str, dict[str, Any]],
) -> dict[str, Any] | None:
    if movie["tmdb"]:
        try:
            found = by_tmdb.get(int(movie["tmdb"]))
            if found:
                return found
        except ValueError:
            pass
    if movie["imdb"]:
        return by_imdb.get(str(movie["imdb"]))
    return None


def delete_radarr(api_key: str, radarr_movie: dict[str, Any]) -> None:
    movie_id = radarr_movie["id"]
    qs = urllib.parse.urlencode(
        {"deleteFiles": "true", "addImportExclusion": "true"}
    )
    http_json(
        "DELETE",
        f"{RADARR_URL}/api/v3/movie/{movie_id}?{qs}",
        {"X-Api-Key": api_key},
    )


def jellyfin_token(db: sqlite3.Connection) -> str:
    row = db.execute(
        "SELECT AccessToken FROM ApiKeys WHERE Name = ? ORDER BY Id LIMIT 1",
        ("arrstack",),
    ).fetchone()
    if row and row[0]:
        return row[0]
    row = db.execute("SELECT AccessToken FROM ApiKeys ORDER BY Id LIMIT 1").fetchone()
    if not row or not row[0]:
        raise RuntimeError("no Jellyfin API keys; create one named arrstack")
    return row[0]


def delete_library_dir(movie: dict[str, Any]) -> str:
    """Jellyfin cannot unlink 0755 radarr/root folders; remove them here."""
    raw = movie.get("path") or ""
    if not raw:
        raise RuntimeError("no jellyfin path")
    target = raw if os.path.isdir(raw) else os.path.dirname(raw)
    real = os.path.realpath(target)
    if real == MOVIES_DIR or not real.startswith(MOVIES_DIR + os.sep):
        raise RuntimeError(f"path outside movies dir: {real}")
    shutil.rmtree(real)
    return real


def delete_jellyfin(token: str, item_id: str) -> None:
    http_json(
        "DELETE",
        f"{JELLYFIN_URL}/Items/{item_id}",
        {"Authorization": f'MediaBrowser Token="{token}"'},
    )


def refresh_jellyfin(token: str) -> None:
    http_json(
        "POST",
        f"{JELLYFIN_URL}/Library/Refresh",
        {"Authorization": f'MediaBrowser Token="{token}"'},
    )


def title(movie: dict[str, Any]) -> str:
    year = movie["year"]
    suffix = f" ({year})" if year else ""
    return f"{movie['name']}{suffix}"


def main() -> int:
    cutoff = datetime.now(timezone.utc) - timedelta(days=STALE_DAYS)
    log(
        f"sweep: Played or >={WATCHED_PCT:.0%} and lastPlayed<={cutoff.date()}"
        f"{' (dry-run)' if DRY_RUN else ''}"
    )

    db = sqlite3.connect(f"file:{JELLYFIN_DB}?mode=ro", uri=True)
    try:
        movies = stale_movies(db, cutoff)
        jf_token = jellyfin_token(db)
    finally:
        db.close()

    if not movies:
        log("nothing stale")
        return 0

    radarr_key = xml_text(RADARR_CONFIG, "ApiKey")
    by_tmdb, by_imdb = radarr_index(radarr_key)
    keep_tag_ids = radarr_keep_ids(radarr_key)

    deleted = 0
    skipped = 0
    for movie in movies:
        label = title(movie)
        last = movie["last_played"].date()
        watched = "Played" if movie["played"] else f"{movie['pct']:.0%}"
        radarr_movie = match_radarr(movie, by_tmdb, by_imdb)
        if radarr_movie and keep_tag_ids.intersection(radarr_movie.get("tags") or []):
            log(f"skip keep-tag: {label}")
            skipped += 1
            continue

        if DRY_RUN:
            via = "radarr" if radarr_movie else "jellyfin"
            log(f"dry-run {via}: {label} ({watched}, last {last})")
            continue

        try:
            if radarr_movie:
                delete_radarr(radarr_key, radarr_movie)
                log(f"deleted radarr: {label} ({watched}, last {last})")
            else:
                try:
                    delete_jellyfin(jf_token, movie["item_id"])
                    log(f"deleted jellyfin: {label} ({watched}, last {last})")
                except Exception:
                    path = delete_library_dir(movie)
                    log(f"deleted files: {label} ({watched}, last {last}) path={path}")
            deleted += 1
        except Exception as exc:
            log(f"error: {label}: {exc}")
            skipped += 1

    if deleted and not DRY_RUN:
        try:
            refresh_jellyfin(jf_token)
            log("requested jellyfin library refresh")
        except Exception as exc:
            log(f"jellyfin refresh failed: {exc}")

    log(f"done: deleted={deleted} skipped={skipped} candidates={len(movies)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
