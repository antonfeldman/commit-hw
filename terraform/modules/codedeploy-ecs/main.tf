# -----------------------------------------------------------------------------
# AWS CodeDeploy blue/green for ECS.
#
# For each service:  new task set ("green") starts in the idle target group ->
#   canary: 10% of production traffic for 5 minutes -> 100% -> old task set
#   ("blue") kept for a rollback window, then terminated.
# A CloudWatch alarm on target 5XX errors stops the deployment and rolls back
# automatically.
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  partition  = data.aws_partition.current.partition
}

resource "aws_codedeploy_app" "this" {
  name             = var.name
  compute_platform = "ECS"
}

# ---- Rollback alarms ----------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  for_each = var.services

  alarm_name          = "${var.name}-${each.key}-target-5xx"
  alarm_description   = "5XX responses from ${each.key} targets - stops and rolls back a CodeDeploy deployment."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = var.rollback_5xx_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = each.value.alb_arn_suffix
  }
}

# ---- Deployment groups --------------------------------------------------------
resource "aws_codedeploy_deployment_group" "this" {
  for_each = var.services

  app_name               = aws_codedeploy_app.this.name
  deployment_group_name  = each.key
  service_role_arn       = aws_iam_role.codedeploy.arn
  deployment_config_name = var.deployment_config_name

  deployment_style {
    deployment_type   = "BLUE_GREEN"
    deployment_option = "WITH_TRAFFIC_CONTROL"
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT" # no manual approval gate
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = var.termination_wait_minutes
    }
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  alarm_configuration {
    enabled = true
    alarms  = [aws_cloudwatch_metric_alarm.target_5xx[each.key].alarm_name]
  }

  ecs_service {
    cluster_name = var.cluster_name
    service_name = each.value.service_name
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [each.value.production_listener_arn]
      }

      target_group {
        name = each.value.target_group_names["blue"]
      }

      target_group {
        name = each.value.target_group_names["green"]
      }
    }
  }
}

# ---- Service role (scoped replacement for the AWSCodeDeployRoleForECS managed policy) ----
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codedeploy.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "codedeploy" {
  name               = "${var.name}-codedeploy"
  description        = "Used by CodeDeploy to run ECS blue/green deployments of ${join(", ", keys(var.services))}"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "codedeploy" {
  statement {
    sid = "ManageTaskSetsOfOwnServices"
    actions = [
      "ecs:DescribeServices",
      "ecs:CreateTaskSet",
      "ecs:UpdateServicePrimaryTaskSet",
      "ecs:DeleteTaskSet",
    ]
    resources = flatten([
      for svc in values(var.services) : [
        "arn:${local.partition}:ecs:${local.region}:${local.account_id}:service/${var.cluster_name}/${svc.service_name}",
        "arn:${local.partition}:ecs:${local.region}:${local.account_id}:task-set/${var.cluster_name}/${svc.service_name}/*",
      ]
    ])
  }

  statement {
    sid = "DescribeLoadBalancing"
    actions = [
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeTargetGroups",
    ]
    resources = ["*"] # Describe* calls do not support resource-level permissions
  }

  statement {
    sid       = "ShiftTrafficOnProductionListenersOnly"
    actions   = ["elasticloadbalancing:ModifyListener", "elasticloadbalancing:ModifyRule"]
    resources = flatten([for svc in values(var.services) : [svc.production_listener_arn, "${replace(svc.production_listener_arn, ":listener/", ":listener-rule/")}/*"]])
  }

  statement {
    sid     = "ReadRollbackAlarms"
    actions = ["cloudwatch:DescribeAlarms"]
    # Read-only alarm metadata. CodeDeploy's call is not authorized against
    # alarm ARNs (fails with IAM_ROLE_PERMISSIONS), so it needs "*".
    resources = ["*"]
  }

  statement {
    sid       = "PassTaskRolesToEcsOnly"
    actions   = ["iam:PassRole"]
    resources = flatten([for svc in values(var.services) : svc.pass_role_arns])

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "codedeploy" {
  name   = "ecs-blue-green"
  role   = aws_iam_role.codedeploy.id
  policy = data.aws_iam_policy_document.codedeploy.json
}
