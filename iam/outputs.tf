output "role_arn" {
  value = aws_iam_role.runner.arn
}

output "instance_profile_name" {
  value = aws_iam_instance_profile.runner.name
}

output "tailscale_auth_key_param" {
  value = var.tailscale_auth_key_param
}
