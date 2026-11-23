"""OpenTelemetry bootstrap shared by the service.

Traces and metrics are exported over OTLP/gRPC to the ADOT collector ECS
service, which forwards traces to AWS X-Ray and metrics to CloudWatch (EMF).
"""

import os

from opentelemetry import metrics, trace
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.extension.aws.resource.ecs import AwsEcsResourceDetector
from opentelemetry.sdk.extension.aws.trace import AwsXRayIdGenerator
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource, get_aggregated_resources
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor


def configure_telemetry(service_name: str) -> None:
    endpoint = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317")

    # service.name + ECS task/cluster attributes (no-op when not running on ECS).
    resource = get_aggregated_resources(
        [AwsEcsResourceDetector()],
        initial_resource=Resource.create({"service.name": service_name}),
    )

    # X-Ray compatible trace IDs (epoch-prefixed) so traces are accepted and searchable.
    tracer_provider = TracerProvider(resource=resource, id_generator=AwsXRayIdGenerator())
    tracer_provider.add_span_processor(
        BatchSpanProcessor(OTLPSpanExporter(endpoint=endpoint, insecure=True))
    )
    trace.set_tracer_provider(tracer_provider)

    metric_reader = PeriodicExportingMetricReader(
        OTLPMetricExporter(endpoint=endpoint, insecure=True),
        export_interval_millis=60_000,
    )
    metrics.set_meter_provider(MeterProvider(resource=resource, metric_readers=[metric_reader]))
