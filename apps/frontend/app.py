"""Frontend service: renders "Hello Commit <X>" where X comes from the backend.

GET  /               page with the current value (read only)
POST /api/increment  button click: increments the counter
GET  /health         excluded from tracing

Both calls go through the backend to PostgreSQL synchronously, so one page load
or one click produces one end-to-end trace: client -> frontend -> backend -> DB.
"""

import logging
import os
import secrets

import requests
from flask import Flask, jsonify, make_response, render_template_string
from opentelemetry import metrics, trace
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor
from waitress import serve

from page import PAGE
from telemetry import configure_telemetry

SERVICE_NAME = os.environ.get("OTEL_SERVICE_NAME", "frontend")
PORT = int(os.environ.get("PORT", "8080"))
BACKEND_URL = os.environ.get("BACKEND_URL", "http://localhost:8081").rstrip("/")
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
TRACE_BASE = (
    f"https://{AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region={AWS_REGION}#xray:traces/"
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger(SERVICE_NAME)

configure_telemetry(SERVICE_NAME)
RequestsInstrumentor().instrument()

meter = metrics.get_meter(SERVICE_NAME)
page_views = meter.create_counter("frontend.page.views", description="Rendered pages")
clicks = meter.create_counter("frontend.button.clicks", description="Successful counter updates")
backend_errors = meter.create_counter("frontend.backend.errors", description="Backend call failures")

app = Flask(__name__)
FlaskInstrumentor().instrument_app(app, excluded_urls="health")


class BackendError(Exception):
    """The backend could not be reached or returned an invalid answer."""


def call_backend(method: str) -> int:
    try:
        resp = requests.request(method, f"{BACKEND_URL}/api/value", timeout=3)
        resp.raise_for_status()
        return int(resp.json()["value"])
    except (requests.RequestException, KeyError, TypeError, ValueError) as exc:
        log.error("backend %s failed: %s", method, exc)
        backend_errors.add(1)
        raise BackendError from exc


def xray_trace_id() -> str:
    """Current trace ID in X-Ray notation: 1-<8 hex epoch>-<24 hex>."""
    trace_id = f"{trace.get_current_span().get_span_context().trace_id:032x}"
    return f"1-{trace_id[:8]}-{trace_id[8:]}"


@app.get("/")
def index():
    value, error, status = None, None, 200
    try:
        value = call_backend("GET")
        page_views.add(1)
    except BackendError:
        error, status = "Backend unavailable", 502

    nonce = secrets.token_urlsafe(16)
    html = render_template_string(
        PAGE, value=value, error=error, nonce=nonce, trace_id=xray_trace_id(), trace_base=TRACE_BASE
    )
    resp = make_response(html, status)
    resp.headers["Cache-Control"] = "no-store"
    resp.headers["X-Content-Type-Options"] = "nosniff"
    resp.headers["Content-Security-Policy"] = (
        f"default-src 'none'; style-src 'nonce-{nonce}'; script-src 'nonce-{nonce}'; "
        "connect-src 'self'; img-src data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
    )
    return resp


@app.post("/api/increment")
def increment():
    try:
        value = call_backend("POST")
    except BackendError:
        return jsonify(error="backend unavailable", trace_id=xray_trace_id()), 502
    clicks.add(1)
    return jsonify(value=value, trace_id=xray_trace_id())


@app.get("/health")
def health():
    return jsonify(status="ok")


if __name__ == "__main__":
    log.info("frontend listening on :%d, backend=%s", PORT, BACKEND_URL)
    serve(app, host="0.0.0.0", port=PORT, threads=8)
