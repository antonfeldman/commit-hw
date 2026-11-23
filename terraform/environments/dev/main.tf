data "aws_caller_identity" "current" {}

locals {
  name       = "${var.project_name}-${var.environment}"
  account_id = data.aws_caller_identity.current.account_id

  ecr_registry = "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"

  # ADOT collector image served from the ECR pull-through cache (private subnets have no internet).
  otel_repository_name = "${module.ecr.pull_through_cache_prefix}/aws-observability/aws-otel-collector"
  otel_image           = "${local.ecr_registry}/${local.otel_repository_name}:${var.otel_collector_version}"
  otel_repository_arn  = "arn:aws:ecr:${var.aws_region}:${local.account_id}:repository/${local.otel_repository_name}"

  backend_url   = "http://backend.${module.ecs_cluster.namespace_name}:${var.backend_port}"
  otlp_endpoint = "http://otel.${module.ecs_cluster.namespace_name}:${var.otlp_grpc_port}"

  db_secret_arn = module.rds.master_user_secret_arn

  # Container health checks use Python (the slim images have no curl).
  app_health_check = {
    for svc, port in { frontend = var.frontend_port, backend = var.backend_port } : svc => [
      "CMD", "python", "-c",
      "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:${port}/health', timeout=3).status == 200 else 1)"
    ]
  }

  otel_collector_config = yamlencode({
    extensions = {
      health_check = { endpoint = "0.0.0.0:13133" }
    }
    receivers = {
      otlp = { protocols = { grpc = { endpoint = "0.0.0.0:${var.otlp_grpc_port}" } } }
    }
    processors = {
      "batch/traces"  = { timeout = "1s", send_batch_size = 50 }
      "batch/metrics" = { timeout = "60s" }
    }
    exporters = {
      # Traces -> AWS X-Ray (service map, trace timeline, per-segment latency).
      awsxray = { region = var.aws_region }
      # Metrics -> CloudWatch via Embedded Metric Format.
      awsemf = {
        region                  = var.aws_region
        namespace               = var.metrics_namespace
        log_group_name          = aws_cloudwatch_log_group.otel_metrics.name
        log_stream_name         = "otel-metrics"
        dimension_rollup_option = "NoDimensionRollup"
      }
    }
    service = {
      extensions = ["health_check"]
      pipelines = {
        traces  = { receivers = ["otlp"], processors = ["batch/traces"], exporters = ["awsxray"] }
        metrics = { receivers = ["otlp"], processors = ["batch/metrics"], exporters = ["awsemf"] }
      }
    }
  })
}

# =============================================================================
# Networking
# =============================================================================
module "network" {
  source = "../../modules/network"

  name                 = local.name
  vpc_cidr_block       = var.vpc_cidr_block
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  data_subnet_cidrs    = var.data_subnet_cidrs
  db_port              = var.db_port
  log_retention_days   = var.log_retention_days
}

module "security_groups" {
  source = "../../modules/security-groups"

  name              = local.name
  aws_region        = var.aws_region
  vpc_id            = module.network.vpc_id
  alb_ingress_cidrs = var.alb_ingress_cidrs
  frontend_port     = var.frontend_port
  backend_port      = var.backend_port
  db_port           = var.db_port
  otlp_grpc_port    = var.otlp_grpc_port
}

module "vpc_endpoints" {
  source = "../../modules/vpc-endpoints"

  name                    = local.name
  aws_region              = var.aws_region
  vpc_id                  = module.network.vpc_id
  subnet_ids              = module.network.private_subnet_ids
  security_group_id       = module.security_groups.vpc_endpoints_sg_id
  gateway_route_table_ids = [module.network.private_route_table_id]
}

# =============================================================================
# Edge, registry, data
# =============================================================================
module "alb" {
  source = "../../modules/alb"

  name              = local.name
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  security_group_id = module.security_groups.alb_sg_id
  frontend_port     = var.frontend_port
}

module "ecr" {
  source = "../../modules/ecr"

  name             = var.project_name
  repository_names = ["frontend", "backend"]
}

module "rds" {
  source = "../../modules/rds"

  name              = local.name
  data_subnet_ids   = module.network.data_subnet_ids
  security_group_id = module.security_groups.rds_sg_id
  port              = var.db_port
  instance_class    = var.db_instance_class
}

# =============================================================================
# ECS cluster + services
# =============================================================================
module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  name                        = local.name
  vpc_id                      = module.network.vpc_id
  service_discovery_namespace = var.service_discovery_namespace
}

module "frontend" {
  source = "../../modules/ecs-service"

  name                 = "frontend"
  aws_region           = var.aws_region
  cluster_arn          = module.ecs_cluster.cluster_arn
  cluster_name         = module.ecs_cluster.cluster_name
  image                = "${module.ecr.repository_urls["frontend"]}:${var.image_tag}"
  ecr_repository_arns  = [module.ecr.repository_arns["frontend"]]
  container_port       = var.frontend_port
  desired_count        = var.app_desired_count
  subnet_ids           = module.network.private_subnet_ids
  security_group_ids   = [module.security_groups.frontend_sg_id]
  health_check_command = local.app_health_check["frontend"]
  log_retention_days   = var.log_retention_days

  attach_load_balancer = true
  target_group_arn     = module.alb.frontend_target_group_arn

  environment = {
    PORT                        = tostring(var.frontend_port)
    BACKEND_URL                 = local.backend_url
    REFRESH_SECONDS             = tostring(var.refresh_seconds)
    OTEL_SERVICE_NAME           = "frontend"
    OTEL_EXPORTER_OTLP_ENDPOINT = local.otlp_endpoint
  }

  # The target group must be attached to a listener before ECS can register targets.
  depends_on = [module.alb]
}

module "backend" {
  source = "../../modules/ecs-service"

  name                 = "backend"
  aws_region           = var.aws_region
  cluster_arn          = module.ecs_cluster.cluster_arn
  cluster_name         = module.ecs_cluster.cluster_name
  image                = "${module.ecr.repository_urls["backend"]}:${var.image_tag}"
  ecr_repository_arns  = [module.ecr.repository_arns["backend"]]
  container_port       = var.backend_port
  desired_count        = var.app_desired_count
  subnet_ids           = module.network.private_subnet_ids
  security_group_ids   = [module.security_groups.backend_sg_id]
  health_check_command = local.app_health_check["backend"]
  log_retention_days   = var.log_retention_days

  enable_service_discovery       = true
  service_discovery_namespace_id = module.ecs_cluster.namespace_id
  service_discovery_name         = "backend"

  environment = {
    PORT                        = tostring(var.backend_port)
    DB_HOST                     = module.rds.address
    DB_PORT                     = tostring(module.rds.port)
    DB_NAME                     = module.rds.database_name
    DB_SSLMODE                  = "require"
    OTEL_SERVICE_NAME           = "backend"
    OTEL_EXPORTER_OTLP_ENDPOINT = local.otlp_endpoint
  }

  # Injected by ECS from the RDS-managed secret; never visible in the task definition.
  secrets = {
    DB_USER     = "${local.db_secret_arn}:username::"
    DB_PASSWORD = "${local.db_secret_arn}:password::"
  }
  secret_arns = [local.db_secret_arn]
}

# ---- OpenTelemetry collector (AWS Distro for OpenTelemetry) -------------------
resource "aws_cloudwatch_log_group" "otel_metrics" {
  name              = "/ecs/${local.name}/otel-metrics"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "otel_collector_task" {
  statement {
    sid = "XRayWrite"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
      "xray:GetSamplingRules",
      "xray:GetSamplingTargets",
      "xray:GetSamplingStatisticSummaries",
    ]
    resources = ["*"] # X-Ray does not support resource-level permissions for these actions
  }

  statement {
    sid = "EmfMetricsToOwnLogGroup"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.otel_metrics.arn}:*"]
  }
}

module "otel_collector" {
  source = "../../modules/ecs-service"

  name                 = "otel-collector"
  aws_region           = var.aws_region
  cluster_arn          = module.ecs_cluster.cluster_arn
  cluster_name         = module.ecs_cluster.cluster_name
  image                = local.otel_image
  ecr_repository_arns  = [local.otel_repository_arn]
  container_port       = var.otlp_grpc_port
  cpu                  = 256
  memory               = 512
  desired_count        = var.otel_collector_desired_count
  subnet_ids           = module.network.private_subnet_ids
  security_group_ids   = [module.security_groups.otel_collector_sg_id]
  health_check_command = ["CMD", "/healthcheck"] # binary shipped in the ADOT image
  log_retention_days   = var.log_retention_days

  allow_pull_through_cache_import = true

  enable_service_discovery       = true
  service_discovery_namespace_id = module.ecs_cluster.namespace_id
  service_discovery_name         = "otel"

  environment = {
    AOT_CONFIG_CONTENT = local.otel_collector_config
  }

  create_task_role_policy = true
  task_role_policy_json   = data.aws_iam_policy_document.otel_collector_task.json
}

# =============================================================================
# Identity: GitHub Actions OIDC + read-only reviewer
# =============================================================================
module "github_oidc" {
  source = "../../modules/iam-github-oidc"

  name                 = local.name
  github_repository    = var.github_repository
  allowed_refs         = var.github_allowed_refs
  ecr_repository_arns  = values(module.ecr.repository_arns)
  create_oidc_provider = var.create_github_oidc_provider
}

module "readonly_reviewer" {
  source = "../../modules/iam-readonly-reviewer"

  user_name   = var.reviewer_user_name
  require_mfa = var.reviewer_require_mfa
}
