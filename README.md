# Hyperswitch (React + Python) on Kubernetes — APM + RUM + K8s monitoring for Datadog **and** Coralogix

Based on [juspay/hyperswitch-react-python](https://github.com/juspay/hyperswitch-react-python).
Built for throw-away clusters such as the **KodeKloud Kubernetes playground**: the cluster is
disposable, this repo is the reusable part. One command rebuilds everything each session.

```
Browser ── Datadog RUM SDK ──────────────────────────────► Datadog RUM
   │    └─ Coralogix RUM SDK ────────────────────────────► Coralogix RUM
   │ traceparent
   ▼
nginx (frontend pod) ──► Flask backend (opentelemetry-instrument = APM)
                               │ OTLP
                               ▼
                         otel-gateway ──┬─► Coralogix (traces, metrics)
                                        └─► Datadog Agent OTLP ─► Datadog APM
Datadog Agent + Cluster Agent  ─► Datadog  (nodes, pods, k8s events, logs)
Coralogix otel-integration      ─► Coralogix (nodes, pods, k8s events, logs)
```

## Layout
| Path | What |
|---|---|
| `server.py`, `Dockerfile.backend` | Flask backend; APM via OpenTelemetry auto-instrumentation (Flask, requests, logging) |
| `src/observability.js`, `Dockerfile.frontend`, `docker/` | React app with Datadog + Coralogix RUM; config written at container start |
| `k8s/monitoring/otel-gateway.yaml` | Collector that fans app telemetry out to both vendors |
| `values/` | Helm values for Datadog Agent and Coralogix otel-integration |
| `k8s/app/` | App manifests (+ optional headless-browser RUM traffic generator) |
| `bootstrap.sh` | Builds the whole stack on a fresh cluster |
| `.github/workflows/build-images.yml` | Builds/pushes images to Docker Hub |

## One-time setup
1. Push this repo to your GitHub. Add repo secrets `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`.
   The workflow builds `hyperswitch-backend` and `hyperswitch-frontend`; make both Docker Hub repos **public**.
2. Accounts / keys:
   * Hyperswitch sandbox: API key + publishable key (app.hyperswitch.io → Developers)
   * Datadog: API key; RUM application (JS) → application ID + client token
   * Coralogix: Send-Your-Data API key; RUM public key; your domain (e.g. `coralogix.in`)
3. `cp .env.example .env` and fill it in. Keep `.env` somewhere safe outside the playground
   (e.g. a private gist / password manager) — you paste it in each session.

## Every KodeKloud session (~5–10 min)
```bash
git clone https://github.com/<you>/<this-repo>.git && cd <this-repo>
vi .env            # paste your saved .env
./bootstrap.sh
./scripts/check.sh
```
Open `http://<node-ip>:30080` (use the playground's port/URL access feature if it has one),
or set `ENABLE_LOADGEN=true` to have an in-cluster headless browser generate RUM sessions.

## Where to look
* **Datadog**: APM → Services → `hyperswitch-backend`; Digital Experience → RUM; Infrastructure → Kubernetes (cluster `kk-MMDD-HHMM`)
* **Coralogix**: APM → `hyperswitch-backend`; RUM → `hyperswitch-frontend`; Infrastructure / Kubernetes dashboard

## Notes
* **RUM ↔ APM link**: both SDKs would write the same `traceparent` header, so `RUM_TRACE_LINK`
  picks one (`datadog` default). Backend traces always go to both vendors.
* Datadog OTLP uses the `datadog` local Service (no hostPort) because the Coralogix agent already
  binds hostPorts 4317/4318.
* kubeadm kubelet certs → `datadog.kubelet.tlsVerify: false`.
* Small playground nodes: if pods are `Pending`/`OOMKilled`, lower requests or turn off the load generator.
* Once a session works, pin `DD_CHART_VERSION` / `CX_CHART_VERSION` in `.env` so later sessions are identical.
* Local dev without k8s: `npm install --legacy-peer-deps`, `npm run start-server`, `npm run start-client`
  (edit `public/config.js` for keys).
