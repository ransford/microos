variable "aws_profile" {
  description = "AWS CLI profile (log in first with `aws sso login --profile <name>`)."
  type        = string
  default     = "sandbox-admin"
}

variable "region" {
  type    = string
  default = "us-west-2"
}

variable "name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "kernel-builder"
}

variable "tailscale_auth_key_param" {
  description = "SSM Parameter Store name holding the Tailscale auth key (SecureString)."
  type        = string
  default     = "/kernel-builder/tailscale-auth-key"
}

variable "ecr_repository" {
  description = "ECR repository the instances push VM images to (created by ../registry)."
  type        = string
  default     = "microos"
}
