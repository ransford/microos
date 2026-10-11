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

# Latest Canonical image for the chosen Ubuntu LTS release.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-*-${var.ubuntu_version}-amd64-server-*"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

data "aws_iam_instance_profile" "runner" {
  name = var.instance_profile_name
}

resource "aws_instance" "builder" {
  count = var.instance_count

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = local.network.private_subnet_id
  vpc_security_group_ids      = [local.network.security_group_id]
  associate_public_ip_address = false
  key_name                    = local.network.key_name
  iam_instance_profile        = data.aws_iam_instance_profile.runner.name

  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    hostname     = "${var.name}-${count.index}"
    region       = var.region
    ts_key_param = var.tailscale_auth_key_param
  })
  user_data_replace_on_change = true

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_gb
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = { Name = "${var.name}-${count.index}" }

  # The NAT route must exist before cloud-init starts fetching packages.
  depends_on = [aws_route.private_default]
}
