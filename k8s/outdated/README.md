# Cloud C2 on Kubernetes (Traefik v3, Distroless, Non-Root)

This folder contains manifests for deploying Cloud C2 behind **Traefik v3** using **IngressRoute** (HTTP→HTTPS) and **IngressRouteTCP** (port 2022). The Deployment runs a **distroless, non-root** image and stores the SQLite DB on a PVC at `/data`.

> Cloud C2 is typically a **single-replica** service when using the default SQLite DB. For HA, you’d need an externalized, supported DB strategy (not included here).

---

## Prerequisites

- **Traefik v3** (CRDs installed; API group `traefik.io/v1alpha1`)
- Traefik entrypoints:
  - `web` → :80
  - `websecure` → :443 (TLS enabled)
  - `ssh` → :2022 (TCP)
- A default `StorageClass` for the PVC or specify one
If using HTTPS:
- A TLS cert secret (e.g., `c2-tls`) in the app namespace for HTTPS at Traefik

> If you manage Traefik with Helm, add an extra entrypoint:
>
> ```yaml
> ports:
>   web:       { exposedPort: 80 }
>   websecure: { exposedPort: 443, tls: { enabled: true } }
>   ssh:
>     port: 2022
>     exposedPort: 2022
> ```
>
> Then create an `IngressRouteTCP` that targets `entryPoints: ["ssh"]`.

---

## What’s included

- `configmap.yaml` – non-secret env (e.g., `reverseProxy=1`, ports)
- `secrets.yaml` – secrets like `setLicenseKey` (**use SOPS/KSOPS in Git**)
- `pvc.yaml` – `ReadWriteOnce` PVC for `/data` (SQLite DB)
- `deployment.yaml` – distroless, non-root container, probes, env wiring
- `service.yaml` – ClusterIP Service exposing HTTP (80) + SSH (2022)
- `traefik-mwiddleware.yaml` – `Middleware` to redirect HTTP→HTTPS
- `traefik-ingressroute.yaml` – `IngressRoute` for web & websecure
- `traefik-ingressroute-tcp.yaml` – `IngressRouteTCP` for SSH relay (2022)

---

## Quick start (kubectl)

```bash
# 1) Namespace (optional)
kubectl create namespace devsec

# 2) Config + Secret + Storage
kubectl apply -f configmap.yaml
kubectl apply -f secret.yaml
kubectl apply -f pvc.yaml

# 3) App + Service
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml

# 4) Traefik routes (HTTP→HTTPS + TCP 2022)
kubectl apply -f traefik-middleware.yaml
kubectl apply -f traefik-ingressroute.yaml
kubectl apply -f traefik-ingressroute-tcp.yaml
```

## Key settings to review

- **Hostname / domain**
  - Set `fqdn` and/or `publicHostname` in the ConfigMap to your real domain.
  - Use the same host in the Traefik `IngressRoute` `Host(...)` rule.

- **Reverse proxy awareness**
  - Set `reverseProxy: "1"` when terminating TLS at Traefik/ingress.

- **TLS termination**
  - In this setup, TLS is terminated at Traefik (`websecure` with a TLS secret).
  - Do **not** set `https`, `certFile`, or `keyFile` in the Pod for this setup.

- **Storage**
  - SQLite DB at `/data/c2.db` on a PVC (`ReadWriteOnce`).
  - Ensure regular backups of the PVC.

- **Security context**
  - Runs as non-root (uid 65532).
  - Use `fsGroup` (or appropriate permissions) so the Pod can write to the PVC.

- **Probes**
  - HTTP liveness/readiness on `/` matching the Service/port that fronts container `8080`.

- **Traefik entrypoints & CRDs**
  - Ensure Traefik **v3** CRDs are installed (`traefik.io/v1alpha1`).
  - EntryPoints: `web` (80), `websecure` (443), and a TCP entryPoint (e.g., `ssh` on 2022) for `IngressRouteTCP`.

- **Replicas / scaling**
  - Keep `replicas: 1` with SQLite.
  - For HA, externalize to a supported DB and implement app-level clustering before scaling.

## Notes / tips

Keep reverseProxy=1 (env) in your ConfigMap so Cloud C2 understands it’s behind Traefik.

If you terminate TLS at Traefik, do not set https=1 / certFile / keyFile in the container; just run HTTP on 8080 → Traefik handles TLS.

Distroless has no shell — liveness/readiness probes must be HTTP (as shown in your Deployment), not exec.

IngressRouteTCP (SSH relay, TCP 2022)

Requires an extra Traefik entryPoint (e.g., ssh) bound to :2022. Example Helm values below. Router matches all SNI; SSH isn’t TLS, so just use HostSNI(\*`)on the TCP router to catch all traffic on the ssh` entryPoint.  
Traefik Docs.
