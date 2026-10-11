#!/usr/bin/env bash
set -euo pipefail

# Publish the existing tested amd64 image; do not rebuild it here.
IMAGE="${IMAGE:-joshuapfritz/hak5c2}"
if (( $# < 1 || $# > 2 )); then
  echo "Usage: $0 <version> [tested-image]" >&2
  echo "Example: $0 3.5.2 hak5c2:test" >&2
  exit 2
fi
VERSION="$1"
SOURCE_IMAGE="${2:-hak5c2:test}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must have the form 3.5.2" >&2
  exit 2
fi
command -v docker >/dev/null
command -v trivy >/dev/null
SOURCE_ID="$(docker image inspect --format '{{.Id}}' "$SOURCE_IMAGE")"
PLATFORM="$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$SOURCE_ID")"
if [[ "$PLATFORM" != "linux/amd64" ]]; then
  echo "This release script supports linux/amd64 only; source is $PLATFORM" >&2
  exit 2
fi
REPORT_DIR="${REPORT_DIR:-reports/$VERSION}"
mkdir -p "$REPORT_DIR"
printf 'Image: %s\nSource: %s\nImage ID: %s\nPlatform: %s\nUTC scan time: %s\n' \
  "$IMAGE" "$SOURCE_IMAGE" "$SOURCE_ID" "$PLATFORM" "$(date -u +%FT%TZ)" \
  | tee "$REPORT_DIR/image.txt"
trivy --version > "$REPORT_DIR/trivy-version.txt"
# Findings are recorded without suppression; scanner failures stop the release.
trivy image --scanners vuln --exit-code 0 "$SOURCE_ID" 2>&1 \
  | tee "$REPORT_DIR/trivy.txt"
trivy image --scanners vuln --exit-code 0 --format json \
  --output "$REPORT_DIR/trivy.json" "$SOURCE_ID"

# Use the captured image ID so retagging the source cannot change this release.
for tag in "$VERSION-amd64" "$VERSION" latest; do
  docker tag "$SOURCE_ID" "$IMAGE:$tag"
done
# Authenticate separately with docker login before invoking this script.
for tag in "$VERSION-amd64" "$VERSION" latest; do
  docker push "$IMAGE:$tag" 2>&1 | tee "$REPORT_DIR/push-$tag.txt"
done
docker image inspect --format '{{json .RepoDigests}}' "$SOURCE_ID" \
  > "$REPORT_DIR/repo-digests.json"
echo "Published $IMAGE:$VERSION-amd64, $IMAGE:$VERSION, and $IMAGE:latest"
