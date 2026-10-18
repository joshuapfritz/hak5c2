
#!/usr/bin/env bash
set -euo pipefail

CURRENT="3.5.2-stable"
API="https://downloads.hak5.org/api/devices/cloudc2/firmwares"

# Fetch firmware metadata
RELEASES=$(curl -fsSL "$API")

# Display available releases (newest first)
echo "Available Hak5 Cloud C2 releases:"
echo
echo "$RELEASES" | jq -r '
  sort_by(.release_date) | reverse | .[] |
  [.version, (.release_date | split("T")[0]), .checksum] | @tsv
' | column -t -N VERSION,DATE,SHA256

# Identify latest release
LATEST=$(echo "$RELEASES" | jq -r 'max_by(.release_date) | .version')
SHA256=$(echo "$RELEASES" | jq -r 'max_by(.release_date) | .checksum')

echo
if [[ "$CURRENT" == "$LATEST" ]]; then
    echo "Cloud C2 is up to date: $CURRENT"
else
    echo "Cloud C2 update available!"
    echo "Current: $CURRENT"
    echo "Latest:  $LATEST"
fi

echo "SHA256:  $SHA256"
