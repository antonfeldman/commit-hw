# Non-secret settings only. Credentials never go in this file.
github_repository = "antonfeldman/commit-hw"

# The repo uses GitHub's immutable OIDC subject (owner/repo numeric IDs, not secret).
# Source: gh api repos/antonfeldman/commit-hw/actions/oidc/customization/sub
github_oidc_subject_prefix = "repo:antonfeldman@57878914/commit-hw@1468523665"

# Initial image tag that seeds the SSM image-tag parameters on the first apply.
# After that the pipeline owns the tags (deploy.yml -> SSM -> CodeDeploy).
image_tag = "def37a3"
