# The VPC, subnets, route tables, security group and key pair live in the
# long-lived ../network stack, which is free while idle. This stack adds the
# billable NAT gateway (with its Elastic IP and the private subnet's default
# route through it) so instances without public IPs can reach apt, kernel.org,
# rustup and Tailscale, and so it goes away with `tofu destroy`.

data "terraform_remote_state" "network" {
  backend = "local"
  config = {
    path = "${path.module}/../network/terraform.tfstate"
  }
}

locals {
  network = data.terraform_remote_state.network.outputs
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.name}-nat" }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = local.network.public_subnet_id
  tags          = { Name = var.name }
}

resource "aws_route" "private_default" {
  route_table_id         = local.network.private_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}
