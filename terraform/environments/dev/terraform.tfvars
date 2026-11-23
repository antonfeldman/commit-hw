# Non-secret settings only. Credentials never go in this file.
github_repository = "antonfeldman/commit-hw"

# Set to the commit SHA of the images pushed to ECR (see README, "Build & push images").
# Override on the command line: terraform apply -var image_tag=$(git rev-parse --short HEAD)
image_tag = "initial"
