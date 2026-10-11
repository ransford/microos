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

# Long-lived network and access config for the kernel builders. Everything
# here is free while idle; anything billable (the instances, and the NAT
# gateway with its Elastic IP and route) lives in the ephemeral ../instance
# stack so that `tofu destroy` there leaves nothing costing money.

data "aws_ec2_instance_type_offerings" "available" {
  location_type = "availability-zone"
  filter {
    name   = "instance-type"
    values = [var.instance_type]
  }
}

locals {
  az = sort(data.aws_ec2_instance_type_offerings.available.locations)[0]
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.name }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = var.name }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.this.id
  availability_zone = local.az
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 0)
  tags              = { Name = "${var.name}-public" }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.this.id
  availability_zone = local.az
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 1)
  tags              = { Name = "${var.name}-private" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "${var.name}-public" }
}

# No routes declared inline: ../instance adds the default route through its
# NAT gateway with a standalone aws_route.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-private" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# No ingress at all: SSH arrives over Tailscale, which only needs outbound.
resource "aws_security_group" "builder" {
  name        = var.name
  description = "Egress-only; access is via Tailscale"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_key_pair" "builder" {
  key_name   = var.name
  public_key = file(pathexpand(var.ssh_public_key_path))
}
