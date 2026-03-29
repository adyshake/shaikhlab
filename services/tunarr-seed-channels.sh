#!/usr/bin/env bash
#
# Seed Tunarr with channel definitions from tunarr-channels.json
# Channels are created as empty shells — you populate them with content
# from your Jellyfin library via the Tunarr web UI.
#
# Usage: ./tunarr-seed-channels.sh [TUNARR_URL]
#   Default TUNARR_URL: http://localhost:8000

set -euo pipefail

TUNARR_URL="${1:-http://localhost:8010}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHANNELS_FILE="${SCRIPT_DIR}/tunarr-channels.json"

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required. Install it first."
  exit 1
fi

if ! command -v curl &>/dev/null; then
  echo "Error: curl is required."
  exit 1
fi

if [[ ! -f "$CHANNELS_FILE" ]]; then
  echo "Error: $CHANNELS_FILE not found"
  exit 1
fi

echo "Tunarr URL: $TUNARR_URL"
echo "Reading channels from: $CHANNELS_FILE"
echo ""

# Check if Tunarr is reachable
if ! curl -sf "${TUNARR_URL}/api/channels" >/dev/null 2>&1; then
  echo "Error: Cannot reach Tunarr at ${TUNARR_URL}"
  echo "Make sure Tunarr is running and accessible."
  exit 1
fi

existing_channels=$(curl -sf "${TUNARR_URL}/api/channels" | jq length)
echo "Existing channels: $existing_channels"
echo ""

channel_count=$(jq '.channels | length' "$CHANNELS_FILE")
echo "Channels to create: $channel_count"
echo "---"

for i in $(seq 0 $((channel_count - 1))); do
  name=$(jq -r ".channels[$i].name" "$CHANNELS_FILE")
  number=$(jq -r ".channels[$i].number" "$CHANNELS_FILE")
  group=$(jq -r ".channels[$i].group" "$CHANNELS_FILE")

  # Check if channel number already exists
  exists=$(curl -sf "${TUNARR_URL}/api/channels" | jq "[.[] | select(.number == $number)] | length")
  if [[ "$exists" -gt 0 ]]; then
    echo "SKIP: CH $number ($name) — already exists"
    continue
  fi

  payload=$(jq -n \
    --arg name "$name" \
    --argjson number "$number" \
    --arg group "$group" \
    '{
      name: $name,
      number: $number,
      groupTitle: $group,
      stealth: false,
      guideMinimumDuration: 300000
    }')

  response=$(curl -sf -X POST "${TUNARR_URL}/api/channels" \
    -H "Content-Type: application/json" \
    -d "$payload" 2>&1) && {
    echo " OK: CH $number — $name [$group]"
  } || {
    echo "FAIL: CH $number — $name (HTTP error)"
  }
done

echo ""
echo "---"
echo "Done! Open ${TUNARR_URL} to add programming from your Jellyfin library."
echo ""
echo "Next steps:"
echo "  1. Go to Settings > Sources and connect Jellyfin (http://127.0.0.1:8096)"
echo "  2. Click each channel and add content from your library"
echo "  3. Access your channels:"
echo "     - M3U:    ${TUNARR_URL}/api/channels/m3u"
echo "     - XMLTV:  ${TUNARR_URL}/api/xmltv.xml"
echo "     - HDHomeRun: Add ${TUNARR_URL} as tuner in Jellyfin Live TV"
