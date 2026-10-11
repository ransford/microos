output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "private_subnet_id" {
  value = aws_subnet.private.id
}

output "private_route_table_id" {
  value = aws_route_table.private.id
}

output "key_name" {
  value = aws_key_pair.builder.key_name
}

output "security_group_id" {
  value = aws_security_group.builder.id
}
