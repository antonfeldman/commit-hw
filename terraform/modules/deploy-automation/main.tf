# -----------------------------------------------------------------------------
# Deployment automation:
#
#   GitHub Actions --put-parameter--> SSM /<name>/<service>/image-tag
#        EventBridge rule (Parameter Store Change) --> Lambda "deployer"
#             --> new ECS task definition revision --> CodeDeploy blue/green
#
# The Lambda has no VPC attachment: it only calls AWS APIs and never reaches the
# workloads, so it needs no network path into the VPC.
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id    = data.aws_caller_identity.current.account_id
  region        = data.aws_region.current.region
  partition     = data.aws_partition.current.partition
  function_name = "${var.name}-ecs-deployer"

  deploy_config = {
    for svc, c in var.services : c.parameter_name => {
      service          = svc
      family           = c.task_definition_family
      container        = c.container_name
      port             = c.container_port
      repository       = c.repository_name
      repository_url   = c.repository_url
      application      = var.codedeploy_app_name
      deployment_group = c.deployment_group_name
    }
  }
}

# ---- Lambda package -------------------------------------------------------------
data "archive_file" "deployer" {
  type        = "zip"
  source_file = "${path.module}/src/handler.py"
  output_path = "${path.module}/.build/ecs-deployer.zip"
}

resource "aws_cloudwatch_log_group" "deployer" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "deployer" {
  function_name    = local.function_name
  description      = "Deploys a new ECS task definition with CodeDeploy blue/green when an image-tag SSM parameter changes"
  role             = aws_iam_role.deployer.arn
  runtime          = "python3.13"
  architectures    = ["arm64"]
  handler          = "handler.handler"
  filename         = data.archive_file.deployer.output_path
  source_code_hash = data.archive_file.deployer.output_base64sha256
  timeout          = 60
  memory_size      = 128

  environment {
    variables = {
      DEPLOY_CONFIG = jsonencode(local.deploy_config)
    }
  }

  tracing_config {
    mode = "Active"
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.deployer.name
  }
}

# A failed deployment start (e.g. a deployment already running) should be
# visible and re-triggered deliberately - not retried silently in the background.
resource "aws_lambda_function_event_invoke_config" "deployer" {
  function_name          = aws_lambda_function.deployer.function_name
  maximum_retry_attempts = 0
}

# ---- EventBridge: SSM parameter change -> Lambda -------------------------------
resource "aws_cloudwatch_event_rule" "image_tag_changed" {
  name        = "${var.name}-image-tag-changed"
  description = "Image-tag SSM parameter created/updated -> ECS blue/green deployment"

  event_pattern = jsonencode({
    source        = ["aws.ssm"]
    "detail-type" = ["Parameter Store Change"]
    detail = {
      name      = [for c in values(var.services) : c.parameter_name]
      operation = ["Create", "Update"]
    }
  })
}

resource "aws_cloudwatch_event_target" "deployer" {
  rule = aws_cloudwatch_event_rule.image_tag_changed.name
  arn  = aws_lambda_function.deployer.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeImageTagRule"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.deployer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.image_tag_changed.arn
}

# ---- IAM: least privilege for the deployer -------------------------------------
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "deployer" {
  name               = local.function_name
  description        = "Execution role of the SSM-triggered ECS blue/green deployer Lambda"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "deployer" {
  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.deployer.arn}:*"]
  }

  statement {
    sid       = "XRayTracing"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"] # X-Ray does not support resource-level permissions
  }

  statement {
    sid       = "ReadImageTagParameters"
    actions   = ["ssm:GetParameter"]
    resources = [for c in values(var.services) : "arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter${c.parameter_name}"]
  }

  statement {
    sid       = "VerifyImageExists"
    actions   = ["ecr:DescribeImages"]
    resources = [for c in values(var.services) : c.repository_arn]
  }

  statement {
    sid       = "TaskDefinitions"
    actions   = ["ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"]
    resources = ["*"] # these ECS actions do not support resource-level permissions
  }

  statement {
    sid       = "TagNewTaskDefinitionsOnly"
    actions   = ["ecs:TagResource"]
    resources = [for c in values(var.services) : "arn:${local.partition}:ecs:${local.region}:${local.account_id}:task-definition/${c.task_definition_family}:*"]

    condition {
      test     = "StringEquals"
      variable = "ecs:CreateAction"
      values   = ["RegisterTaskDefinition"]
    }
  }

  statement {
    sid       = "PassTaskRolesToEcsOnly"
    actions   = ["iam:PassRole"]
    resources = flatten([for c in values(var.services) : c.pass_role_arns])

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  statement {
    sid       = "StartDeployments"
    actions   = ["codedeploy:CreateDeployment"]
    resources = [for c in values(var.services) : c.deployment_group_arn]
  }

  statement {
    sid       = "ReadDeploymentConfig"
    actions   = ["codedeploy:GetDeploymentConfig"]
    resources = [var.deployment_config_arn]
  }

  statement {
    sid       = "RegisterRevisions"
    actions   = ["codedeploy:RegisterApplicationRevision", "codedeploy:GetApplicationRevision"]
    resources = [var.codedeploy_app_arn]
  }
}

resource "aws_iam_role_policy" "deployer" {
  name   = "ecs-deployer"
  role   = aws_iam_role.deployer.id
  policy = data.aws_iam_policy_document.deployer.json
}
