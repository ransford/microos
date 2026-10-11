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

resource "aws_iam_instance_profile" "runner" {
  name = "${var.name}-runner"
  role = aws_iam_role.runner.name
}
