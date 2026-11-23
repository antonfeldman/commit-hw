# Non-secret settings only. Credentials never go in this file.
github_repository = "antonfeldman/commit-hw"

# Commit SHA of the images currently deployed (pushed to ECR by scripts/build-and-push.sh or CI).
# To deploy a new build: push the images, update this value, then plan + apply.
image_tag = "def37a3"
