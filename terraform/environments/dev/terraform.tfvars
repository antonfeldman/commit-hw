# Non-secret settings only. Credentials never go in this file.
github_repository = "antonfeldman/commit-hw"

# The repo uses GitHub's immutable OIDC subject (owner/repo numeric IDs, not secret).
# Source: gh api repos/antonfeldman/commit-hw/actions/oidc/customization/sub
github_oidc_subject_prefix = "repo:antonfeldman@57878914/commit-hw@1468523665"

# Image tags in the task definitions that Terraform registers. Newer versions are
# deployed by GitHub Actions (deploy.yml -> CodeDeploy), not by changing these.
image_tags = {
  frontend = "9b13d16"
  backend  = "5ee4fbd"
}
