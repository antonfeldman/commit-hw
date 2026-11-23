"""Frontend service: renders "Hello Commit <X>" where X comes from the backend.

Every page load calls the backend synchronously, so a single browser request
produces one end-to-end trace: client -> frontend -> backend -> PostgreSQL.
The page auto-refreshes every REFRESH_SECONDS, so the value is pulled
periodically and each refresh is its own trace.
"""

import html
import logging
import os

import requests
from flask import Flask, Response, jsonify
from opentelemetry import metrics
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor
from waitress import serve

from telemetry import configure_telemetry

SERVICE_NAME = os.environ.get("OTEL_SERVICE_NAME", "frontend")
PORT = int(os.environ.get("PORT", "8080"))
BACKEND_URL = os.environ.get("BACKEND_URL", "http://localhost:8081").rstrip("/")
REFRESH_SECONDS = int(os.environ.get("REFRESH_SECONDS", "5"))

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger(SERVICE_NAME)

configure_telemetry(SERVICE_NAME)
RequestsInstrumentor().instrument()

meter = metrics.get_meter(SERVICE_NAME)
page_views = meter.create_counter("frontend.page.views", description="Rendered pages")
backend_errors = meter.create_counter("frontend.backend.errors", description="Backend call failures")

app = Flask(__name__)
FlaskInstrumentor().instrument_app(app, excluded_urls="health")

PAGE = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta http-equiv="refresh" content="{refresh}">
  <title>Hello Commit</title>
</head>
<body>
  <h1>{message}</h1>
  <p>Value pulled from the database via the backend. Refreshes every {refresh}s.</p>
  <p><small>v2 &middot; served over HTTPS &middot; deployed by GitHub Actions &rarr; SSM &rarr; CodeDeploy blue/green</small></p>
</body>
</html>
"""


def render(message: str, status: int) -> Response:
    body = PAGE.format(refresh=REFRESH_SECONDS, message=html.escape(message))
    return Response(body, status=status, mimetype="text/html")


@app.get("/")
def index():
    try:
        resp = requests.get(f"{BACKEND_URL}/api/value", timeout=3)
        resp.raise_for_status()
        value = int(resp.json()["value"])
    except (requests.RequestException, KeyError, ValueError) as exc:
        log.error("backend call failed: %s", exc)
        backend_errors.add(1)
        return render("Hello Commit (backend unavailable)", 502)

    page_views.add(1)
    return render(f"Hello Commit {value}", 200)


@app.get("/health")
def health():
    return jsonify(status="ok")


if __name__ == "__main__":
    log.info("frontend listening on :%d, backend=%s", PORT, BACKEND_URL)
    serve(app, host="0.0.0.0", port=PORT, threads=8)
