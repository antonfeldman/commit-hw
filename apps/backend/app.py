"""Backend service: reads/increments a counter in RDS PostgreSQL.

GET  /api/value -> {"value": <int>}   reads the counter
POST /api/value -> {"value": <int>}   increments it and returns the new value
GET  /health    -> {"status": "ok"}   (excluded from tracing)

Each /api/value call is one DB statement, traced as a SQL span.
"""

import logging
import os
import time

import psycopg
from flask import Flask, jsonify
from opentelemetry import metrics, trace
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.psycopg import PsycopgInstrumentor
from psycopg.conninfo import make_conninfo
from waitress import serve

from telemetry import configure_telemetry

SERVICE_NAME = os.environ.get("OTEL_SERVICE_NAME", "backend")
PORT = int(os.environ.get("PORT", "8080"))

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger(SERVICE_NAME)

configure_telemetry(SERVICE_NAME)
PsycopgInstrumentor().instrument(enable_commenter=False)

tracer = trace.get_tracer(SERVICE_NAME)
meter = metrics.get_meter(SERVICE_NAME)
db_queries = meter.create_counter("backend.db.queries", description="Counter queries executed")

app = Flask(__name__)
FlaskInstrumentor().instrument_app(app, excluded_urls="health")


def _conninfo() -> str:
    # DB_USER / DB_PASSWORD are injected by ECS from the RDS-managed Secrets Manager secret.
    return make_conninfo(
        host=os.environ["DB_HOST"],
        port=os.environ.get("DB_PORT", "5432"),
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        sslmode=os.environ.get("DB_SSLMODE", "require"),
        connect_timeout=5,
    )


def init_schema(retries: int = 30, delay: float = 5.0) -> None:
    """Create the counter table once. Retries while RDS / networking come up.

    Wrapped in a parent span so the startup SQL is attributed to the backend
    service in X-Ray instead of appearing as an orphan database node.
    SpanKind.SERVER makes the X-Ray exporter name the segment after the service
    ("backend") rather than the span, so it merges into the existing map node.
    """
    with tracer.start_as_current_span("init_schema", kind=trace.SpanKind.SERVER) as span:
        for attempt in range(1, retries + 1):
            span.set_attribute("db.init.attempts", attempt)
            try:
                with psycopg.connect(_conninfo()) as conn:
                    conn.execute(
                        "CREATE TABLE IF NOT EXISTS hello_counter ("
                        " id INTEGER PRIMARY KEY,"
                        " value BIGINT NOT NULL)"
                    )
                    conn.execute(
                        "INSERT INTO hello_counter (id, value) VALUES (1, 0) ON CONFLICT (id) DO NOTHING"
                    )
                log.info("schema ready")
                return
            except psycopg.OperationalError as exc:
                span.add_event("database not ready", {"attempt": attempt, "error": str(exc)})
                log.warning("database not ready (attempt %d/%d): %s", attempt, retries, exc)
                time.sleep(delay)
        span.set_status(trace.StatusCode.ERROR, "database never became available")
        raise RuntimeError("database never became available")


def _query_value(sql: str):
    with psycopg.connect(_conninfo()) as conn:
        row = conn.execute(sql).fetchone()
    db_queries.add(1)
    return jsonify(value=row[0])


@app.get("/api/value")
def get_value():
    return _query_value("SELECT value FROM hello_counter WHERE id = 1")


@app.post("/api/value")
def increment_value():
    return _query_value("UPDATE hello_counter SET value = value + 1 WHERE id = 1 RETURNING value")


@app.get("/health")
def health():
    return jsonify(status="ok")


if __name__ == "__main__":
    init_schema()
    log.info("backend listening on :%d", PORT)
    serve(app, host="0.0.0.0", port=PORT, threads=8)
