#!/usr/bin/env python3
"""
Hyperswitch demo backend (Flask).

Changes vs upstream:
  * keys / URLs come from environment variables (no hard-coded secrets)
  * outbound call uses `requests` so OpenTelemetry traces the Hyperswitch API call
  * /healthz endpoint for Kubernetes probes
  * structured logs carry trace_id / span_id for log <-> trace correlation

APM is NOT in this file: the container starts the app with
`opentelemetry-instrument`, which auto-instruments Flask + requests.
"""
import logging
import os

import requests
from flask import Flask, jsonify

HYPERSWITCH_API_KEY = os.environ.get("HYPERSWITCH_API_KEY", "")
HYPERSWITCH_BASE_URL = os.environ.get("HYPERSWITCH_BASE_URL", "https://sandbox.hyperswitch.io")

logging.basicConfig(
    level=logging.INFO,
    force=True,
    format="%(asctime)s %(levelname)s [%(name)s] "
           "trace_id=%(otelTraceID)s span_id=%(otelSpanID)s service=%(otelServiceName)s - %(message)s",
)
# When running without opentelemetry-instrument (local dev) the otel* fields don't exist.
_old_factory = logging.getLogRecordFactory()


def _record_factory(*args, **kwargs):
    record = _old_factory(*args, **kwargs)
    for field in ("otelTraceID", "otelSpanID", "otelServiceName"):
        if not hasattr(record, field):
            setattr(record, field, "0")
    return record


logging.setLogRecordFactory(_record_factory)
log = logging.getLogger("hyperswitch-backend")

app = Flask(__name__)


def calculate_order_amount(items):
    # Calculate the order total on the server so the client can't manipulate it
    return 1400


@app.get("/healthz")
def healthz():
    return jsonify(status="ok")


@app.post("/create-payment")
def create_payment():
    if not HYPERSWITCH_API_KEY:
        log.error("HYPERSWITCH_API_KEY is not set")
        return jsonify(error="HYPERSWITCH_API_KEY is not configured"), 500
    try:
        resp = requests.post(
            f"{HYPERSWITCH_BASE_URL}/payments",
            json={"amount": 100, "currency": "USD", "customer_id": "hyperswitch_customer"},
            headers={"Accept": "application/json", "api-key": HYPERSWITCH_API_KEY},
            timeout=15,
        )
        data = resp.json()
        if resp.status_code >= 400 or "client_secret" not in data:
            log.warning("Hyperswitch returned %s: %s", resp.status_code, data)
            return jsonify(error=data), 502
        log.info("payment created payment_id=%s", data.get("payment_id"))
        return jsonify(client_secret=data["client_secret"])
    except Exception as e:  # noqa: BLE001
        log.exception("create-payment failed")
        return jsonify(error=str(e)), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=4242)
