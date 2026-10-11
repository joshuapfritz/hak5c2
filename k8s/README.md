# Hak5 Cloud C2 container examples

These examples target the updated joshuapfritz/hak5c2 wrapper and Cloud C2 3.5.2. Publish the tested build to `joshuapfritz/hak5c2:3.5.2` before deploying. For immutable deployment, replace that tag with the published image digest.

## Files

Four core manifests: `configmap.yaml`, `pvc.yaml`, `deployment.yaml`, and `service.yaml`. `traefik.yaml` optionally adds HTTPS, an HTTP redirect, and device SSH routing. `secrets.template.yaml` is an empty optional Secret template for license and recovery settings. All resources use `devsec`; change it consistently if needed.

The default configuration assumes HTTPS termination at a reverse proxy. The container serves HTTP on 8080. There is no required license Secret: enter the license during initial browser setup. Optional recovery settings can be provided through a Secret named `c2-secrets`.

## Kubernetes

1. Set `hostname` in `configmap.yaml` to the server IP or DNS name reachable by users and devices.
2. Select a storage class in `pvc.yaml` if there is no default.
3. Publish the tested image and confirm the Deployment image reference.
4. Apply the core manifests:

```bash
kubectl create namespace devsec --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f configmap.yaml -f pvc.yaml -f deployment.yaml -f service.yaml
kubectl -n devsec rollout status deployment/cloudc2
kubectl -n devsec logs deployment/cloudc2
```

Complete browser setup with the token from the logs and your license, then verify login after a Pod restart. A replacement Pod should recover the account and database from `/data`. The setup-token file in `/app` is not persisted.

For a direct HTTP deployment, set `reverseProxy: "false"` and remove `reverseProxyPort`. Publish the Service through your chosen network arrangement. A local UI smoke test can use `kubectl -n devsec port-forward service/cloudc2 8080:80`; that does not establish device connectivity.

### Optional Traefik

Replace `c2.example.com` in both HTTP routes with the configured hostname. Traefik needs its CRDs and `web` (HTTP), `websecure` (HTTPS), and dedicated `ssh` (raw TCP) entrypoints. Create the `c2-tls` TLS Secret in `devsec`, or adapt the TLS block to your existing certificate configuration, then apply:

```bash
kubectl apply -f traefik.yaml
```

Keep `https: "false"`, `reverseProxy: "true"`, and `reverseProxyPort: "443"` when Traefik terminates TLS on public port 443. The SSH entrypoint must be exposed separately through Traefik's Service and any firewall/NAT. Its internal name is `ssh`; this example assumes external TCP 2022, matching C2's `sshport`. HTTP ingress does not carry SSH. The wildcard TCP match is intentional for non-TLS SSH.

### Storage and security

Use one replica. `Recreate` avoids overlapping old and new Pods during Deployment updates to the SQLite-backed service; it is not a general database fencing mechanism. Back up the PVC. UID/GID and fsGroup are 65532; volume permission support depends on the storage driver.

The image needs static `mv` support and a writable `/app` for Overseer startup. This example therefore leaves the root filesystem writable, while dropping capabilities, disallowing privilege escalation, and using RuntimeDefault seccomp. Read-only root filesystem support needs a separate, tested runtime-binary arrangement.

Startup and readiness probes check that the HTTP port accepts TCP connections. They do not validate login, HTTP responses, or device SSH health. No liveness probe is included until a suitable application health check is established.

## Docker test

Run from a directory where `test-data` should live. Open the UI from a browser on the Docker host, or through an SSH tunnel, because these bindings are loopback-only.

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
  joshuapfritz/hak5c2:3.5.2
docker logs hak5c2-test
```

Browse to `http://localhost:8080`, complete setup and login, run `docker restart hak5c2-test`, and verify login again. This is a local UI test; use a reachable hostname and published ports for devices.

## Secrets

The Deployment optionally loads environment variables from the `c2-secrets` Secret in `devsec`. A Secret is not required for normal startup or browser-based licensing. Use it for sensitive settings such as `setLicenseKey` and `setPass`, or temporary recovery settings.

Copy the template, replace `stringData: {}` with a `stringData:` mapping, and uncomment only the values needed for your operation:

```bash
cp secrets.template.yaml secrets.yaml
# Edit secrets.yaml locally before applying it.
kubectl apply -f secrets.yaml
kubectl -n devsec rollout restart deployment/cloudc2
kubectl -n devsec rollout status deployment/cloudc2
```

The template is deliberately empty: applying it unchanged passes no flags. Quote every value, including booleans. For account recovery, supply both `recoverAccount` and `setPass`; `setLicenseKey`, `setEdition`, `resetTOTP`, `allowIP`, and `resetFirewall` are available when needed. Avoid defining the same environment name in both the ConfigMap and Secret.

Changes to the Secret are picked up by newly started Pods, so restart the Deployment after each change. After recovery succeeds, remove the recovery keys from the Secret and restart again so subsequent starts do not repeat those actions. If the Secret was created solely for recovery, delete it and restart instead:

```bash
kubectl -n devsec delete secret c2-secrets
kubectl -n devsec rollout restart deployment/cloudc2
```

Keep populated `secrets.yaml` files out of Git unless encrypted with SOPS/KSOPS or managed through another secret system. Kubernetes Secret encoding does not itself provide encryption. Commit the empty template; ignore the local plaintext file. These are startup environment variables, not a `_FILE` interface, so file-backed Docker secrets need an additional integration rather than being automatically read by this wrapper.

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

## Scan the tested build

```bash
set -o pipefail
trivy image --scanners vuln hak5c2:test 2>&1 | tee hak5c2-trivy.txt
trivy image --scanners vuln --format json --output hak5c2-trivy.json hak5c2:test
```

The supplied October 10, 2026 scan reported 178 findings in `/app/c2`, zero in `/app/entrypoint`, and one UNKNOWN Debian tzdata advisory (DLA-4792-1). These are scanner findings, not confirmed exploit counts. The copied BusyBox binary was not separately listed in that summary; it should not be described as independently verified clean. Retain upstream findings and record image digest, C2 release, and Trivy version with published results.

## References

- [Hak5 installation and setup](https://documentation.hak5.org/cloud-c2/getting-started/installation-and-setup)
- [Kubernetes Deployment strategy](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Kubernetes security context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
- [Traefik TCP rules](https://doc.traefik.io/traefik/reference/routing-configuration/tcp/routing/rules-and-priority/)
