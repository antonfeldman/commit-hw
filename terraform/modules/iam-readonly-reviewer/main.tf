# -----------------------------------------------------------------------------
# Read-only IAM user for the reviewer.
#   - AWS managed ReadOnlyAccess (view everything, change nothing)
#   - Console access only: no access keys are created
#   - MFA enforced: until the user signs in with MFA, everything except
#     setting up their own MFA device and changing their own password is denied
#   - The console password is NOT managed here (it would be stored in state);
#     it is set once with the AWS CLI - see README.
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

resource "aws_iam_user" "reviewer" {
  name          = var.user_name
  force_destroy = true # allows destroy after a password/MFA device was added out-of-band
}

resource "aws_iam_user_policy_attachment" "read_only" {
  user       = aws_iam_user.reviewer.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "enforce_mfa" {
  statement {
    sid = "AllowSelfServiceMfaAndPassword"
    actions = [
      "iam:ChangePassword",
      "iam:GetUser",
      "iam:GetLoginProfile",
      "iam:CreateVirtualMFADevice",
      "iam:EnableMFADevice",
      "iam:ListMFADevices",
      "iam:ResyncMFADevice",
    ]
    resources = [
      aws_iam_user.reviewer.arn,
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:mfa/$${aws:username}",
    ]
  }

  statement {
    sid       = "AllowListVirtualMfaDevices"
    actions   = ["iam:ListVirtualMFADevices", "iam:GetAccountPasswordPolicy"]
    resources = ["*"]
  }

  statement {
    sid    = "DenyEverythingElseWithoutMfa"
    effect = "Deny"
    not_actions = [
      "iam:ChangePassword",
      "iam:GetUser",
      "iam:GetLoginProfile",
      "iam:CreateVirtualMFADevice",
      "iam:EnableMFADevice",
      "iam:ListMFADevices",
      "iam:ListVirtualMFADevices",
      "iam:ResyncMFADevice",
      "iam:GetAccountPasswordPolicy",
      "sts:GetSessionToken",
    ]
    resources = ["*"]

    condition {
      test     = "BoolIfExists"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["false"]
    }
  }
}

resource "aws_iam_user_policy" "enforce_mfa" {
  count = var.require_mfa ? 1 : 0

  name   = "enforce-mfa"
  user   = aws_iam_user.reviewer.name
  policy = data.aws_iam_policy_document.enforce_mfa.json
}
