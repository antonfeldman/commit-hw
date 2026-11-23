# -----------------------------------------------------------------------------
# Private ECR repositories for the application images, plus a pull-through
# cache for ECR Public so the ADOT collector image can be pulled from inside a
# VPC that has no internet access.
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "this" {
  for_each = toset(var.repository_names)

  name                 = "${var.name}/${each.value}"
  image_tag_mutability = "IMMUTABLE" # a tag always points to the same, scanned image
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the last ${var.keep_last_images} images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.keep_last_images
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_pull_through_cache_rule" "ecr_public" {
  ecr_repository_prefix = var.pull_through_cache_prefix
  upstream_registry_url = "public.ecr.aws"
}
