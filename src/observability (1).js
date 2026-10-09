/**
 * Browser RUM for BOTH Datadog and Coralogix.
 *
 * Config is NOT baked into the bundle. nginx writes /config.js at container
 * start-up from env vars, which sets window.__APP_CONFIG__. The same image
 * therefore works in every cluster / every KodeKloud session.
 *
 * Trace linking (RUM -> backend APM):
 *   Both SDKs patch fetch/XHR and would each try to write a `traceparent`
 *   header on the same request. Only one can win, so RUM_TRACE_LINK picks
 *   which vendor injects it ("datadog" | "coralogix" | "none").
 *   The backend trace still goes to BOTH vendors either way.
 */
import { datadogRum } from "@datadog/browser-rum";
import { CoralogixRum } from "@coralogix/browser";

const cfg = window.__APP_CONFIG__ || {};
const on = (v) => String(v).toLowerCase() === "true";
const origin = window.location.origin;
const link = (cfg.rumTraceLink || "datadog").toLowerCase();

if (on(cfg.ddRumEnabled) && cfg.ddRumAppId && cfg.ddRumClientToken) {
  datadogRum.init({
    applicationId: cfg.ddRumAppId,
    clientToken: cfg.ddRumClientToken,
    site: cfg.ddSite || "datadoghq.com",
    service: cfg.frontendService || "hyperswitch-frontend",
    env: cfg.env || "dev",
    version: cfg.version || "0.0.0",
    sessionSampleRate: 100,
    sessionReplaySampleRate: 20,
    trackUserInteractions: true,
    trackResources: true,
    trackLongTasks: true,
    defaultPrivacyLevel: "mask-user-input",
    // Same-origin API (nginx proxies /create-payment), W3C traceparent header
    allowedTracingUrls:
      link === "datadog" ? [{ match: origin, propagatorTypes: ["tracecontext"] }] : [],
    traceSampleRate: 100,
  });
  console.info("[obs] Datadog RUM initialised");
}

if (on(cfg.cxRumEnabled) && cfg.cxRumPublicKey) {
  CoralogixRum.init({
    public_key: cfg.cxRumPublicKey,
    application: cfg.appName || "hyperswitch",
    environment: cfg.env || "dev",
    version: cfg.version || "0.0.0",
    coralogixDomain: cfg.cxRumDomain || "AP1",
    sessionConfig: { sessionSampleRate: 100 },
    traceParentInHeader: {
      enabled: link === "coralogix",
      options: { allowedTracingUrls: [new RegExp("/create-payment")] },
    },
  });
  console.info("[obs] Coralogix RUM initialised");
}
