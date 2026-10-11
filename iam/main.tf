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

data "aws_caller_identity" "current" {}

locals {
  tailscale_param_arn = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${var.tailscale_auth_key_param}"
  ecr_repository_arn  = "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/${var.ecr_repository}"
}

# Role assumed by the kernel-builder EC2 instances.
resource "aws_iam_role" "runner" {
  name        = "${var.name}-runner"
  description = "EC2 role for ephemeral ${var.name} instances"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Break-glass shell access via SSM Session Manager (no inbound ports needed).
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.runner.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Lets the instance read the Tailscale auth key at boot. The parameter is a
# SecureString encrypted with the AWS-managed aws/ssm key, whose key policy
# already permits decryption via SSM for principals in this account.
resource "aws_iam_role_policy" "tailscale_key" {
  name = "read-tailscale-auth-key"
  role = aws_iam_role.runner.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter"]
      Resource = local.tailscale_param_arn
    }]
  })
}

# Lets image/push-oci push VM images to the ../registry ECR repository, and
# image/make-ami upload a disk to an EBS snapshot (EBS direct APIs, used by
# coldsnap) and register it as an AMI.
resource "aws_iam_role_policy" "publish_vm_image" {
  name = "publish-vm-image"
  role = aws_iam_role.runner.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
        ]
        Resource = local.ecr_repository_arn
      },
      {
        Effect   = "Allow"
        Action   = ["ebs:StartSnapshot", "ebs:PutSnapshotBlock", "ebs:CompleteSnapshot"]
        Resource = "arn:aws:ec2:${var.region}::snapshot/*"
      },
      # Describe* can't be scoped to resources.
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeImages", "ec2:DescribeSnapshots"]
        Resource = "*"
      },
      # Tagging and registering only touch AMIs and snapshots, never instances
      # or other resources in the account.
      {
        Effect = "Allow"
        Action = ["ec2:CreateTags", "ec2:RegisterImage"]
        Resource = [
          "arn:aws:ec2:${var.region}::image/*",
          "arn:aws:ec2:${var.region}::snapshot/*",
        ]
      },
    ]
  })
}

resource "aws_iam_instance_profile" "runner" {
  name = "${var.name}-runner"
  role = aws_iam_role.runner.name
}
