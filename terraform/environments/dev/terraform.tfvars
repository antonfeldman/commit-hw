# Non-secret settings only. Credentials never go in this file.
github_repository = "antonfeldman/commit-hw"

# The repo uses GitHub's immutable OIDC subject (owner/repo numeric IDs, not secret).
# Source: gh api repos/antonfeldman/commit-hw/actions/oidc/customization/sub
github_oidc_subject_prefix = "repo:antonfeldman@57878914/commit-hw@1468523665"

# Commit SHA of the images currently deployed (pushed to ECR by scripts/build-and-push.sh or CI).
# To deploy a new build: push the images, update this value, then plan + apply.
image_tag = "def37a3"
