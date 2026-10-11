terraform {
  required_version = ">= 1.8"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  profile = var.aws_profile
  region  = var.region

  default_tags {
    tags = {
      Project   = var.name
      ManagedBy = "opentofu"
    }
  }
}

# Long-lived ECR repository for the VM images that image/push-oci publishes as
# OCI artifacts. It costs only storage, a few cents a month at most.
resource "aws_ecr_repository" "vm" {
  name                 = var.repository_name
  image_tag_mutability = "MUTABLE" # `latest` moves with each release
  force_delete         = true      # let `tofu destroy` remove it with images in it
}

resource "aws_ecr_lifecycle_policy" "vm" {
  repository = aws_ecr_repository.vm.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the ${var.keep_images} most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.keep_images
      }
      action = { type = "expire" }
    }]
  })
}
