# Hak5 Cloud C2 in a container
[![Docker Hub](https://img.shields.io/badge/Docker%20Hub-joshuapfritz%2Fhack5c2-blue?logo=docker)](https://hub.docker.com/r/joshuapfritz/hack5c2)

A nonroot distroless container with a Go entrypoint exposing every Cloud C2 3.5.2 command-line flag through environment variables. It supports Docker, Compose, and Kubernetes. The official Hak5 archive is downloaded at build time; C2 binaries are not stored in this repository. Hak5 licensing and EULA still apply.

## Runtime

The fetch stage extracts the official C2 executable and supplies static BusyBox `mv`. The wrapper stage builds with Go 1.27.2. The final distroless image runs as UID/GID 65532 without a shell or package manager. `/app` must remain writable because C2's Overseer code moves its executable at startup; read-only root filesystem support is not implemented. Persist the database at `/data`.

## Build arguments

| Argument | Example | Purpose |
| --- | --- | --- |
| RELEASE | `3.5.2-stable` | Hak5 archive release identifier; defaults to `latest` |
| TARGET | `amd64_linux` | Archive binary selector; current examples support linux/amd64 |
| C2_SHA256 | ZIP SHA-256 | Optional downloaded-archive verification; empty skips verification |
| URL | Full archive URL | Override the download endpoint |

`ALPINE_MIRROR` is no longer a supported argument. See [build.md](build.md) for build, test, scan, and publish commands.

## Docker

For a local UI test on the Docker host:

```bash
sudo install -d -o 65532 -g 65532 -m 0700 "$PWD/test-data"
docker run -d --name hak5c2-test \
  --user 65532:65532 \
  --security-opt no-new-privileges:true --cap-drop ALL \
  -p 127.0.0.1:8080:8080 -p 127.0.0.1:2022:2022 \
  --mount type=bind,src="$PWD/test-data",dst=/data \
  -e hostname=localhost -e db=/data/c2.db \
  -e listenport=8080 -e sshport=2022 \
  -e https=false -e reverseProxy=false -e nobanner=true \
  hak5c2:test
docker logs hak5c2-test
```

Open `http://localhost:8080` from the Docker host or through an SSH tunnel. Complete setup with the logged token and your license, log in, restart the container, and verify login again. Loopback bindings are for this UI test; devices need a reachable hostname and published ports. For a released image, substitute `joshuapfritz/hak5c2:3.5.2`.

## Compose

Create the bind-mount directory with the correct ownership, set a client-facing hostname, and start the published image:

```bash
sudo install -d -o 65532 -g 65532 -m 0700 ./data
export C2_HOSTNAME=armitage.cyberpunkcity.org
docker compose up -d
docker compose logs cloudc2
```

The example publishes HTTP 8080 and device SSH 2022 on the host. It runs directly over HTTP; for HTTPS termination at a proxy, set `reverseProxy: "true"` and `reverseProxyPort: "443"`, while retaining `https: "false"`. Configure proxy routing and device TCP reachability separately.

Distroless has no shell. Recreate containers after changing environment settings. Do not add `--read-only` until runtime binary relocation has been addressed.

## Secrets

Sensitive settings use the same environment names as native flags. For Docker, an environment file can supply temporary recovery values:

```dotenv
recoverAccount=your-username
setPass=your-temporary-password
```

Save this locally as `secrets.env`, restrict its permissions, and pass `--env-file ./secrets.env` to `docker run` before the image name. For Compose, uncomment the `env_file` block in `docker-compose.yml`, then run `docker compose up -d --force-recreate cloudc2`. The file is optional for normal startup; enter the license through browser setup unless performing a license recovery operation.

Remove temporary recovery values and recreate the container after recovery. Do not commit plaintext secrets, database files, or setup tokens. Environment files are plaintext and container environment values are accessible to users with Docker control. Docker file-based secrets are not automatically consumed by this wrapper; it has no `_FILE` interface.

For Kubernetes, use an optional `c2-secrets` Secret through `envFrom.secretRef`, as shown in the Kubernetes examples. Keep ordinary settings in the ConfigMap, encrypt populated Secrets with SOPS/KSOPS when committing them, and restart Pods after Secret changes. Mount TLS certificate/private-key files read-only and configure `certFile`/`keyFile` with their in-container paths rather than storing file contents in those variables.

## Every native flag is configurable

Environment names are case-sensitive and match the native flag without its leading dash. Native arguments after the image name override matching environment settings. Boolean environment values accept Go's `strconv.ParseBool` forms; prefer `true` or `false`. Empty/unset booleans retain C2 defaults. Explicit `false` does not enable a flag. Empty/unset string settings use upstream defaults, except `db`.

| Environment variable | Type | Behavior |
| --- | --- | --- |
| hostname | string | Required explicit server IP or DNS name |
| db | string | Container default `/data/c2.db` |
| allowIP | string | Recovery: allow an IP through the application firewall |
| certFile | string | Custom certificate path |
| keyFile | string | Custom private key path |
| debug | boolean | Upstream debug logging; also enables verbose logging |
| https | boolean | Enable C2-managed HTTPS |
| listenip | string | Upstream default `0.0.0.0` |
| listenport | string | Upstream default `8080` |
| nobanner | boolean | Disable startup ASCII banner |
| recoverAccount | string | Recovery account username |
| resetFirewall | boolean | Recovery: reset application firewall |
| resetTOTP | string | Recovery: reset named user's TOTP |
| reverseProxy | boolean | Enable reverse-proxy awareness |
| reverseProxyPort | string | Public UI port behind a proxy |
| setEdition | string | Recovery edition: community, pro, or teams |
| setLicenseKey | string | Recovery license key |
| setPass | string | Recovery password for recoverAccount |
| showLicense | boolean | Recovery: print license key |
| sshport | string | Upstream default `2022` |
| v | boolean | Timestamped stdout |

Aliases: `fqdn` supplies hostname only when `hostname` is unset; `verbose` supplies `v` only when `v` is unset/empty. No container-name or POD_IP/POD_NAME fallback. Help (`-h` or `-help`) bypasses the hostname requirement. `C2_EXTRA` is not supported: pass native arguments directly, preserving shell quoting.

HTTPS is not auto-enabled by certificate paths. Set `https=true` when C2 terminates TLS, mount certificate/key files if using custom TLS, and arrange the required ports. Hak5 documents a DNS name as required for HTTPS. For proxy termination, leave C2 HTTPS disabled.

Recovery settings should be temporary. Inject sensitive values through your secret-management workflow, then remove them after recovery. The wrapper does not log its arguments, but C2 can print setup tokens or licenses when explicitly requested.

## Kubernetes

Use the separate Kubernetes examples: ConfigMap, PVC, Deployment, Service, optional Secret template, and optional combined Traefik routes. Keep one replica with a Recreate update strategy. The examples use UID/GID and fsGroup 65532, capability dropping, no privilege escalation, and RuntimeDefault seccomp. Traefik HTTPS terminates outside C2; device SSH uses a separate raw TCP entrypoint.

## Vulnerability reporting

The supplied October 10, 2026 scan of the updated image reports:

| Component | Findings |
| --- | ---: |
| Hak5 C2 executable | 178 |
| Go entrypoint | 0 |
| Debian tzdata | 1 UNKNOWN advisory |

These counts apply to the scanned image and vulnerability database, not future builds. DLA-4792-1 is a timezone-database update advisory. Dependency findings are not confirmed exploitable vulnerability counts. The copied BusyBox binary was not separately listed in that scan summary; this does not establish independent clean coverage for it. Builder packages are not all present in the final image, but the Go toolchain version is embedded in the compiled wrapper and can generate final-image findings.

`release.sh` records fresh Trivy table/JSON results without suppressing upstream findings and publishes the exact existing tested image. See [build.md](build.md).

## References

- [Hak5 installation and setup](https://documentation.hak5.org/cloud-c2/getting-started/installation-and-setup)
- [Docker Compose service configuration](https://docs.docker.com/reference/compose-file/services/)
