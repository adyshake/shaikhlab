# Hardlink completed Transmission torrents into Audiobookshelf libraries.
#
# Tags (case-insensitive, set in the Transmission UI):
#   audiobook     -> /data/fun/library/audiobooks
#   podcast       -> /data/fun/library/podcasts
#   abs-imported  -> already processed (added by the RPC sweep)
#
# Two entry points, same script:
#   1) Transmission script-torrent-done: TR_TORRENT_* is set; hardlink that
#      torrent immediately. No RPC needed.
#   2) systemd timer: sweep RPC for completed tagged torrents (covers tagging
#      after the download finished) and mark them abs-imported.
#
# Hardlinks (same filesystem as /data/transmission) so Transmission can keep
# seeding until the ratio limit; deleting the torrent later leaves the library
# copy.

set -euo pipefail

TAG_AUDIOBOOK=audiobook
TAG_PODCAST=podcast
TAG_DONE=abs-imported

has_label() {
  local needle="$1"
  local haystack="${2:-}"
  printf '%s' "$haystack" | tr ',' '\n' | tr '[:upper:]' '[:lower:]' | grep -qxF "$needle"
}

destination_for_labels() {
  local labels="${1:-}"
  if has_label "$TAG_AUDIOBOOK" "$labels"; then
    printf '%s' "$ABS_AUDIOBOOKS"
  elif has_label "$TAG_PODCAST" "$labels"; then
    printf '%s' "$ABS_PODCASTS"
  fi
}

hardlink_torrent() {
  local name="$1" src_dir="$2" dest_root="$3"
  local safe src dest

  safe=$(printf '%s' "$name" | tr '/' '_')
  if [ -z "$safe" ] || [ "$safe" = "." ] || [ "$safe" = ".." ]; then
    echo "skip: unsafe torrent name: $name" >&2
    return 1
  fi

  src="$src_dir/$name"
  if [ ! -e "$src" ]; then
    echo "skip: source missing: $src" >&2
    return 1
  fi

  if [ -f "$src" ]; then
    dest="$dest_root/${safe%.*}"
    if [ -z "${safe%.*}" ]; then
      dest="$dest_root/$safe"
    fi
    if [ -e "$dest" ]; then
      echo "already imported: $dest"
      return 0
    fi
    mkdir -p "$dest"
    cp -al "$src" "$dest/"
  else
    dest="$dest_root/$safe"
    if [ -e "$dest" ]; then
      echo "already imported: $dest"
      return 0
    fi
    cp -al "$src" "$dest"
  fi

  chmod -R g+rX "$dest"
  chgrp -R media "$dest" || true
  echo "imported: $src -> $dest"
}

import_from_env() {
  local labels dest_root
  labels="${TR_TORRENT_LABELS:-}"
  dest_root=$(destination_for_labels "$labels")
  if [ -z "$dest_root" ]; then
    exit 0
  fi
  echo "torrent-done: $TR_TORRENT_NAME (labels=$labels)"
  # Never fail the hook — Transmission retries a non-zero done-script
  # and *arr completions would also surface as errors. The timer retries.
  hardlink_torrent "$TR_TORRENT_NAME" "$TR_TORRENT_DIR" "$dest_root" || true
}

rpc() {
  local body="$1"
  local response="$WORKDIR/rpc-body"
  local headers="$WORKDIR/rpc-headers"
  local extra=()
  local code

  if [ -n "${SESSION_ID:-}" ]; then
    extra=(-H "X-Transmission-Session-Id: $SESSION_ID")
  fi

  code=$(curl -sS -u "$TRANSMISSION_USER:$TRANSMISSION_PASSWORD" \
    "${extra[@]}" \
    -D "$headers" -o "$response" -w "%{http_code}" \
    -H "Content-Type: application/json" \
    --data-binary "$body" \
    "$TRANSMISSION_RPC_URL") || true

  if [ "$code" = "409" ]; then
    SESSION_ID=$(awk 'tolower($1) == "x-transmission-session-id:" {print $2; exit}' "$headers" | tr -d '\r')
    extra=(-H "X-Transmission-Session-Id: $SESSION_ID")
    code=$(curl -sS -u "$TRANSMISSION_USER:$TRANSMISSION_PASSWORD" \
      "${extra[@]}" \
      -D "$headers" -o "$response" -w "%{http_code}" \
      -H "Content-Type: application/json" \
      --data-binary "$body" \
      "$TRANSMISSION_RPC_URL")
  fi

  if [ "$code" != "200" ]; then
    echo "transmission RPC HTTP ${code:-000}" >&2
    cat "$response" >&2 || true
    return 1
  fi
  cat "$response"
}

mark_imported() {
  local id="$1" labels_json="$2"
  local new_labels payload
  new_labels=$(printf '%s' "$labels_json" | jq -c '. + ["abs-imported"] | unique')
  payload=$(jq -n --argjson id "$id" --argjson labels "$new_labels" \
    '{method:"torrent-set",arguments:{ids:[$id],labels:$labels}}')
  rpc "$payload" >/dev/null
}

sweep_rpc() {
  local cred="${CREDENTIALS_DIRECTORY:-}/transmission-rpc"
  if [ ! -f "$cred" ]; then
    echo "missing transmission RPC credentials at $cred" >&2
    exit 1
  fi
  TRANSMISSION_PASSWORD=$(jq -r '."rpc-password"' "$cred")

  local listing
  listing=$(rpc '{"method":"torrent-get","arguments":{"fields":["id","name","labels","percentDone","downloadDir"]}}')

  local row id name dir labels dest_root labels_json
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    id=$(printf '%s' "$row" | jq -r '.id')
    name=$(printf '%s' "$row" | jq -r '.name')
    dir=$(printf '%s' "$row" | jq -r '.downloadDir')
    labels=$(printf '%s' "$row" | jq -r '[.labels[]?] | join(",")')
    labels_json=$(printf '%s' "$row" | jq -c '.labels // []')
    dest_root=$(destination_for_labels "$labels")
    if [ -z "$dest_root" ]; then
      continue
    fi
    echo "sweep: $name (id=$id labels=$labels)"
    if hardlink_torrent "$name" "$dir" "$dest_root"; then
      mark_imported "$id" "$labels_json"
    fi
  done < <(printf '%s' "$listing" | jq -c '
    .arguments.torrents[]
    | select((.percentDone // 0) >= 0.999)
    | select((.labels // []) | map(ascii_downcase) | index("abs-imported") | not)
    | select((.labels // []) | map(ascii_downcase) | (index("audiobook") or index("podcast")))
  ')
}

: "${ABS_AUDIOBOOKS:?ABS_AUDIOBOOKS is required}"
: "${ABS_PODCASTS:?ABS_PODCASTS is required}"
: "${TRANSMISSION_USER:?TRANSMISSION_USER is required}"
: "${TRANSMISSION_RPC_URL:?TRANSMISSION_RPC_URL is required}"

if [ -n "${TR_TORRENT_NAME:-}" ]; then
  import_from_env
  exit 0
fi

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
sweep_rpc
