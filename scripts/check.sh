#!/usr/bin/env bash
# Quick health check of the observability pipeline.
set -uo pipefail
echo "== Pods"; kubectl get pods -n monitoring; kubectl get pods -n app
echo; echo "== Datadog agent status (APM / OTLP / kubelet)"
POD=$(kubectl -n monitoring get pods -l app=datadog -o name | head -1)
[ -n "$POD" ] && kubectl -n monitoring exec "$POD" -c agent -- agent status 2>/dev/null \
  | grep -E -A3 "OTLP|APM Agent|kubelet|API Keys status" | head -40
echo; echo "== otel-gateway errors (empty = good)"
kubectl -n monitoring logs deploy/otel-gateway --tail=200 | grep -iE "error|fail" | tail -10
echo; echo "== Generate a backend trace"
kubectl -n app run curl-test --rm -i --restart=Never --image=curlimages/curl:8.10.1 -- \
  -s -X POST http://hyperswitch-frontend.app.svc.cluster.local/create-payment -H 'Content-Type: application/json' -d '{}'
echo; echo "== Backend logs (look for trace_id=<hex>, not 0)"
kubectl -n app logs deploy/hyperswitch-backend --tail=5
