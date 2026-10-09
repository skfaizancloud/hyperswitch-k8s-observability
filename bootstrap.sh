#!/usr/bin/env bash
# One command to turn a fresh KodeKloud Kubernetes playground into:
#   Hyperswitch app (React + Python) + APM + RUM + K8s monitoring
#   for BOTH Datadog and Coralogix.
# Idempotent: safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------- 0. config ----------
[ -f .env ] && set -a && . ./.env && set +a
for v in REGISTRY HYPERSWITCH_API_KEY HYPERSWITCH_PUBLISHABLE_KEY DD_API_KEY CORALOGIX_PRIVATE_KEY CORALOGIX_DOMAIN; do
  [ -n "${!v:-}" ] || die "$v is not set (fill in .env)"
done
: "${IMAGE_TAG:=latest}" "${APP_ENV:=kodekloud}" "${DD_SITE:=datadoghq.com}"
: "${DD_RUM_ENABLED:=false}" "${DD_RUM_APP_ID:=}" "${DD_RUM_CLIENT_TOKEN:=}"
: "${CX_RUM_ENABLED:=false}" "${CX_RUM_PUBLIC_KEY:=}" "${RUM_TRACE_LINK:=datadog}" "${ENABLE_LOADGEN:=false}"
: "${CLUSTER_NAME:=kk-$(date +%m%d-%H%M)}"     # new name per session = no mixing with old data
: "${APP_NAME:=faizan-apps-olly}"               # application name shown in Datadog + Coralogix
# lowercase version for service names (Datadog lowercases service names anyway)
APP_SLUG=$(printf '%s' "$APP_NAME" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-')
if [ -z "${CX_RUM_DOMAIN:-}" ]; then
  case "$CORALOGIX_DOMAIN" in
    coralogix.com) CX_RUM_DOMAIN=EU1 ;;   eu2.coralogix.com) CX_RUM_DOMAIN=EU2 ;;
    coralogix.us)  CX_RUM_DOMAIN=US1 ;;   cx498.coralogix.com) CX_RUM_DOMAIN=US2 ;;
    coralogix.in)  CX_RUM_DOMAIN=AP1 ;;   coralogixsg.com) CX_RUM_DOMAIN=AP2 ;;
    ap3.coralogix.com) CX_RUM_DOMAIN=AP3 ;;
    *) die "Can't map CORALOGIX_DOMAIN=$CORALOGIX_DOMAIN to a RUM domain; set CX_RUM_DOMAIN" ;;
  esac
fi
export IMAGE_TAG APP_ENV DD_SITE DD_RUM_ENABLED DD_RUM_APP_ID DD_RUM_CLIENT_TOKEN \
       CX_RUM_ENABLED CX_RUM_PUBLIC_KEY CX_RUM_DOMAIN RUM_TRACE_LINK CLUSTER_NAME APP_NAME APP_SLUG
echo "app=$APP_NAME (services: $APP_SLUG-backend, $APP_SLUG-frontend)"
echo "cluster=$CLUSTER_NAME  env=$APP_ENV  images=$REGISTRY/*:$IMAGE_TAG  cx=$CORALOGIX_DOMAIN($CX_RUM_DOMAIN)  dd=$DD_SITE"

# ---------- 1. tools ----------
log "Checking tools"
kubectl get nodes >/dev/null || die "kubectl can't reach the cluster"
if ! command -v helm >/dev/null; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi
if ! command -v envsubst >/dev/null; then
  (apt-get update -qq && apt-get install -y -qq gettext-base) >/dev/null || die "install gettext-base for envsubst"
fi

apply_ns()     { kubectl create ns "$1" --dry-run=client -o yaml | kubectl apply -f - >/dev/null; }
apply_secret() { local ns=$1 name=$2; shift 2
                 kubectl -n "$ns" create secret generic "$name" "$@" --dry-run=client -o yaml | kubectl apply -f - >/dev/null; }

# ---------- 2. namespaces + secrets ----------
log "Namespaces and secrets"
apply_ns monitoring; apply_ns app
apply_secret monitoring datadog-secret  --from-literal=api-key="$DD_API_KEY"
apply_secret monitoring coralogix-keys  --from-literal=PRIVATE_KEY="$CORALOGIX_PRIVATE_KEY"
apply_secret app        hyperswitch-keys --from-literal=api-key="$HYPERSWITCH_API_KEY"
kubectl -n monitoring create configmap cluster-info \
  --from-literal=CLUSTER_NAME="$CLUSTER_NAME" --from-literal=CORALOGIX_DOMAIN="$CORALOGIX_DOMAIN" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# ---------- 3. Helm repos ----------
log "Helm repos"
helm repo add datadog https://helm.datadoghq.com >/dev/null 2>&1 || true
helm repo add coralogix-charts-virtual https://cgx.jfrog.io/artifactory/coralogix-charts-virtual >/dev/null 2>&1 || true
helm repo update >/dev/null

# ---------- 4. Datadog: node agent + cluster agent + OTLP intake ----------
log "Installing Datadog"
helm upgrade --install datadog datadog/datadog -n monitoring \
  ${DD_CHART_VERSION:+--version "$DD_CHART_VERSION"} \
  -f values/datadog.yaml \
  --set datadog.site="$DD_SITE" --set datadog.clusterName="$CLUSTER_NAME" \
  --set "datadog.tags[0]=project:$APP_SLUG"

# ---------- 5. Coralogix: node agent + cluster collector ----------
log "Installing Coralogix otel-integration"
helm upgrade --install otel-coralogix-integration coralogix-charts-virtual/otel-integration -n monitoring \
  ${CX_CHART_VERSION:+--version "$CX_CHART_VERSION"} \
  --render-subchart-notes -f values/coralogix.yaml \
  --set global.domain="$CORALOGIX_DOMAIN" --set global.clusterName="$CLUSTER_NAME" \
  --set global.defaultApplicationName="$APP_NAME"

# ---------- 6. fan-out collector (app APM -> both vendors) ----------
log "Deploying otel-gateway"
kubectl apply -f k8s/monitoring/otel-gateway.yaml
kubectl -n monitoring rollout restart deploy/otel-gateway >/dev/null   # pick up new keys/config

# ---------- 7. application ----------
log "Deploying Hyperswitch app"
VARS='${REGISTRY} ${IMAGE_TAG} ${APP_ENV} ${APP_NAME} ${APP_SLUG} ${HYPERSWITCH_PUBLISHABLE_KEY} ${DD_RUM_ENABLED} ${DD_RUM_APP_ID} ${DD_RUM_CLIENT_TOKEN} ${DD_SITE} ${CX_RUM_ENABLED} ${CX_RUM_PUBLIC_KEY} ${CX_RUM_DOMAIN} ${RUM_TRACE_LINK}'
export REGISTRY HYPERSWITCH_PUBLISHABLE_KEY
envsubst "$VARS" < k8s/app/app.yaml | kubectl apply -f -
kubectl -n app rollout restart deploy/hyperswitch-backend deploy/hyperswitch-frontend >/dev/null

if [ "$ENABLE_LOADGEN" = "true" ]; then
  log "Deploying RUM load generator"
  kubectl apply -f k8s/app/loadgen.yaml
fi

# ---------- 8. wait + summary ----------
log "Waiting for rollouts (this can take a few minutes on a fresh playground)"
for d in monitoring/otel-gateway monitoring/datadog-cluster-agent app/hyperswitch-backend app/hyperswitch-frontend; do
  kubectl -n "${d%%/*}" rollout status deploy/"${d##*/}" --timeout=300s || echo "  (still starting: $d)"
done
kubectl -n monitoring rollout status ds/datadog --timeout=300s || true

log "Done"
kubectl get pods -n monitoring -o wide; kubectl get pods -n app -o wide
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
cat <<MSG

Frontend:  http://$NODE_IP:30080   (NodePort 30080 on any node)
Cluster name in Datadog / Coralogix:  $CLUSTER_NAME
Quick test from the terminal (creates a backend trace):
  curl -s -X POST http://$NODE_IP:30080/create-payment -H 'Content-Type: application/json' -d '{}'
Health check:  ./scripts/check.sh
MSG
