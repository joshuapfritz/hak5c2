# Build, test, and publish

The release script publishes an existing tested linux/amd64 image. It does not rebuild or download a potentially different upstream release before pushing.

## Build

The Dockerfile should use `golang:1.27.2-alpine3.24` for the wrapper, and include static BusyBox `mv` support and nonroot ownership of `/app`. Build the versioned Hak5 archive, using its release identifier:

```bash
docker build --pull --platform linux/amd64 \
  --build-arg RELEASE=3.5.2-stable \
  --build-arg TARGET=amd64_linux \
  -t hak5c2:test .
```

`RELEASE` selects Hak5's download identifier; it is separate from the Docker image tag. Confirm that the runtime prints Cloud C2 v3.5.2 before publishing under 3.5.2. If Hak5 changes the identifier, use the actual identifier rather than relabeling a different binary.

Optional archive verification:

```bash
docker build --pull --platform linux/amd64 \
  --build-arg RELEASE=3.5.2-stable \
  --build-arg TARGET=amd64_linux \
  --build-arg C2_SHA256=YOUR_VERIFIED_ARCHIVE_SHA256 \
  -t hak5c2:test .
```

The checksum is for the downloaded ZIP, not the extracted executable. An empty checksum skips verification. A checksum obtained from the same download is a reproducibility reference, not independent proof of authenticity. Use the checksum you recorded for the archive being released.

## Test

Run the Docker example in README against `hak5c2:test`. Confirm the explicit hostname is displayed, browser setup/login works, and login still works after restart. Device connectivity and proxy TLS are separate checks. Do not use `--read-only` with the current image.

## Publish exactly the tested build

```bash
docker login
bash release.sh 3.5.2 hak5c2:test
```

The script verifies linux/amd64, captures the image ID, saves table/JSON Trivy reports and scanner version under `reports/3.5.2`, then tags and pushes that same image as:

- `joshuapfritz/hak5c2:3.5.2-amd64`
- `joshuapfritz/hak5c2:3.5.2`
- `joshuapfritz/hak5c2:latest`

Existing destination tags are updated. Upstream findings are retained and do not block publication; a scanner or push error does stop the script. Pushes are sequential and not transactional: an error can leave only some tags published. No multi-platform manifest is created. `TARGET` alone does not make the Go wrapper multi-architecture.

Overrides:

```bash
IMAGE=yourname/hak5c2 REPORT_DIR=reports/custom bash release.sh 3.5.2 hak5c2:test
```

## Git

Review `git status` and `git diff` before committing. Include source, Dockerfile, documentation, examples, and the intended scan reports. Exclude databases, test-data, local secrets, setup-token files, downloaded executables, and credentials. Stage explicit paths appropriate to your repository layout; do not blindly stage the entire working tree. Commit and push your current branch after review.

For deployed workloads, use the published digest from the recorded push output when immutable image identity is needed.
