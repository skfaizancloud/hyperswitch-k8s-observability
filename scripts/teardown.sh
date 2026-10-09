#!/usr/bin/env bash
# Remove everything (the playground is wiped anyway when the session ends).
helm uninstall datadog otel-coralogix-integration -n monitoring || true
kubectl delete ns app monitoring --ignore-not-found
kubectl delete clusterrole,clusterrolebinding otel-gateway --ignore-not-found
