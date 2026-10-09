#!/bin/sh
# Writes window.__APP_CONFIG__ from env vars so one image works in every cluster.
set -e
cat > /usr/share/nginx/html/config.js <<CFG
window.__APP_CONFIG__ = {
  env: "${APP_ENV:-dev}",
  version: "${APP_VERSION:-0.0.0}",
  frontendService: "${FRONTEND_SERVICE:-hyperswitch-frontend}",
  hyperswitchPublishableKey: "${HYPERSWITCH_PUBLISHABLE_KEY:-}",
  ddRumEnabled: "${DD_RUM_ENABLED:-false}",
  ddRumAppId: "${DD_RUM_APP_ID:-}",
  ddRumClientToken: "${DD_RUM_CLIENT_TOKEN:-}",
  ddSite: "${DD_SITE:-datadoghq.com}",
  cxRumEnabled: "${CX_RUM_ENABLED:-false}",
  cxRumPublicKey: "${CX_RUM_PUBLIC_KEY:-}",
  cxRumDomain: "${CX_RUM_DOMAIN:-AP1}",
  rumTraceLink: "${RUM_TRACE_LINK:-datadog}"
};
CFG
echo "40-write-config.sh: wrote config.js (env=${APP_ENV:-dev}, dd=${DD_RUM_ENABLED:-false}, cx=${CX_RUM_ENABLED:-false})"
