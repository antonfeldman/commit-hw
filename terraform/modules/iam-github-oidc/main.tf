# -----------------------------------------------------------------------------
# GitHub Actions -> AWS via OpenID Connect. No long-lived access keys anywhere:
# each workflow run gets short-lived STS credentials for this role, and only
# when the OIDC token comes from the allowed repository + branch.
# -----------------------------------------------------------------------------

locals {
  github_oidc_url = "token.actions.githubusercontent.com"

  # GitHub "immutable subject" format embeds the numeric owner/repo IDs
  # (repo:owner@<owner_id>/name@<repo_id>), so a deleted-and-recreated repo with
  # the same name cannot assume the role. Falls back to the classic format.
  subject_prefix = coalesce(var.oidc_subject_prefix, "repo:${var.github_repository}")
  provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : (
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.github_oidc_url}"
  )

  task_definition_arns = [
    for family in var.task_definition_families :
    "arn:aws:ecs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:task-definition/${family}:*"
  ]
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Only one GitHub OIDC provider can exist per account; set create_oidc_provider = false to reuse it.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://${local.github_oidc_url}"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Pin the trust to this repository and these refs (e.g. main branch) only.
    condition {
      test     = "StringLike"
      variable = "${local.github_oidc_url}:sub"
      values   = [for ref in var.allowed_refs : "${local.subject_prefix}:ref:${ref}"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name                 = "${var.name}-github-actions"
  description          = "Assumed by GitHub Actions (${var.github_repository}) via OIDC to push images to ECR and trigger deployments"
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "permissions" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # does not support resource-level permissions
  }

  statement {
    sid = "PushToProjectRepositoriesOnly"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = var.ecr_repository_arns
  }

  # Deploy = register a task definition revision with the new image, then start a
  # CodeDeploy blue/green deployment. The pipeline cannot update the ECS services
  # or the load balancers itself: CodeDeploy does that with its own role.
  dynamic "statement" {
    for_each = var.enable_deploy_permissions ? [1] : []

    content {
      sid       = "ReadTaskDefinitions"
      actions   = ["ecs:DescribeTaskDefinition"]
      resources = ["*"] # does not support resource-level permissions
    }
  }

  dynamic "statement" {
    for_each = var.enable_deploy_permissions ? [1] : []

    content {
      sid       = "RegisterOwnTaskDefinitions"
      actions   = ["ecs:RegisterTaskDefinition"]
      resources = local.task_definition_arns
    }
  }

  dynamic "statement" {
    for_each = var.enable_deploy_permissions ? [1] : []

    content {
      sid       = "TagNewTaskDefinitionsOnly"
      actions   = ["ecs:TagResource"]
      resources = local.task_definition_arns

      condition {
        test     = "StringEquals"
        variable = "ecs:CreateAction"
        values   = ["RegisterTaskDefinition"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.enable_deploy_permissions ? [1] : []

    content {
      sid       = "PassTaskRolesToEcsOnly"
      actions   = ["iam:PassRole"]
      resources = var.pass_role_arns

      condition {
        test     = "StringEquals"
        variable = "iam:PassedToService"
        values   = ["ecs-tasks.amazonaws.com"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.enable_deploy_permissions ? [1] : []

    content {
      sid       = "StartAndWatchDeployments"
      actions   = ["codedeploy:CreateDeployment", "codedeploy:GetDeployment"]
      resources = var.deployment_group_arns
    }
  }

  dynamic "statement" {
    for_each = var.enable_deploy_permissions ? [1] : []

    content {
      sid       = "ReadDeploymentConfig"
      actions   = ["codedeploy:GetDeploymentConfig"]
      resources = [var.deployment_config_arn]
    }
  }

  dynamic "statement" {
    for_each = var.enable_deploy_permissions ? [1] : []

    content {
      sid       = "RegisterRevisions"
      actions   = ["codedeploy:RegisterApplicationRevision", "codedeploy:GetApplicationRevision"]
      resources = [var.codedeploy_app_arn]
    }
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "ecr-push"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.permissions.json
}
