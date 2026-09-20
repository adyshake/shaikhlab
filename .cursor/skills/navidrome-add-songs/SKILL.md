---
name: navidrome-add-songs
description: >-
  Add music to the svr1shaikh Navidrome library as 320 kbps MP3 (never FLAC).
  Use when the user wants to add songs, albums, or tracks to Navidrome,
  Amperfy, the music server, or /data/fun/library/music; or to transcode
  existing library FLACs down to MP3.
---

# Add songs to Navidrome

Library lives on **svr1shaikh** at `/data/fun/library/music`. Navidrome
(`music.adnanshaikh.com`, Amperfy) scans that folder. **Store 320 kbps
CBR MP3 only** — never copy FLACs into the library. They are huge and
Navidrome already transcodes to MP3 on stream.

## Defaults

- Codec: `libmp3lame`, **320 kbps CBR** (`-b:a 320k`)
- Layout: `Artist/Album/NN - Artist - Title.mp3`
- Tags + embedded cover: keep song fields; **strip scraper junk** (below)
- Skip continuous DJ mixes unless the user asks for them
- Do not re-encode files that are already 320 kbps MP3

Match an **existing artist directory name exactly** (list first). macOS
NFD vs NFC `ë` can create a second `Tiësto` folder.

## Workflow (new files from the Mac)

1. **Probe** with `ffprobe`. If it is not already 320 kbps MP3, transcode.
   Always strip junk tags (even on an already-320 file) before upload.
2. **Name** from tags: track number, first `ARTIST` before `;`, `TITLE`.
   Album folder should follow neighbors (`Club Life, Vol. 2 - Miami`, not
   the raw tag `Club Life - Volume 2 Miami`).
3. **Stage** locally, then rsync to `adnan@svr1shaikh:~/navidrome-upload/`.
4. **Install** with sudo (`adnan` is not in `media`):

```bash
sudo rsync -a --chown=root:media \
  --chmod=Du=rwx,Dg=rwxs,Do=rx,Fu=rw,Fg=rw,Fo=r \
  ~/navidrome-upload/ /data/fun/library/music/
rm -rf ~/navidrome-upload
```

5. **Scan**: `sudo systemctl restart navidrome` (ScanOnStartup). Confirm:

```bash
journalctl -u navidrome --since "1 min ago" --no-pager | grep -E "Scanner:|ready"
```

Expect `tracksImported=N` for new folders. Then delete the local staging dir.

## Strip non-song metadata

Navidrome shows `COMMENT` in the UI. Downloaders leave junk there and in
custom TXXX frames. **Drop these** on every add/transcode, and when
cleaning the library. Stream-copy (`-c copy`); do not re-encode.

**Strip**
- `COMMENT` / `comment` / `description` (Spotify/Tidal/GitHub URLs, SpotiFLAC)
- Any tag whose value is an `http://` or `https://` URL
- `TIDAL_*` (`TIDAL_TRACK_URL`, `TIDAL_ALBUM_URL`, `TIDAL_TRACK_ID`,
  `TIDAL_ALBUM_ID`, `TIDAL_DATA`)
- `SPOTIFY_*`, `encoded_by`

**Keep** title, artist, album, album_artist, track, disc, date, composer,
copyright, publisher, genre, ISRC, UPC, BPM, ReplayGain, iTunes advisory,
cover art.

Rewrite keepers with `-map_metadata -1` then `-metadata key=value` for
each kept tag (clearing `COMMENT=` is not enough for `TIDAL_*` TXXX
frames). ffmpeg may re-add `encoder`; that is fine.

## Transcode command

Temp name **must** end in `.mp3` (ffmpeg will not mux `.mp3.partial`).
Fall back to audio-only if cover copy fails. Delete a source FLAC only
after the MP3 verifies (`ffprobe` bitrate ≥ 280000, size > 20 KB).
Strip junk in the same pass (do not `-map_metadata 0` blindly).

```bash
ffmpeg -y -hide_banner -loglevel error -i "$src" \
  -map 0:a -map 0:v? \
  -c:a libmp3lame -b:a 320k -c:v copy \
  -map_metadata -1 \
  -metadata title="$title" -metadata artist="$artist" \
  -metadata album="$album" -metadata album_artist="$album_artist" \
  -metadata track="$track" -metadata date="$date" \
  -id3v2_version 3 -write_id3v1 1 \
  -f mp3 "$tmp.part.mp3"
mv -f "$tmp.part.mp3" "$dest.mp3"
```

Copy every kept tag from ffprobe, not only the ones in the snippet.

On the server, `ffmpeg` is not on PATH. Use Navidrome's binary:

```bash
journalctl -u navidrome --no-pager | grep -m1 "Found ffmpeg"
```

## Workflow (shrink FLACs already on the server)

Stop Navidrome, transcode in place next to each `.flac`, verify, delete
the FLAC, start Navidrome. Scanner reports `Scanner: Found moved files`
when the same tracks change extension. Leave no leftover `.flac` or
`.part.mp3`.
