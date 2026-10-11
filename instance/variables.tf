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
  description = "Name prefix for all resources; also the Tailscale hostname prefix."
  type        = string
  default     = "kernel-builder"
}

variable "instance_count" {
  type    = number
  default = 1
}

variable "instance_type" {
  type    = string
  default = "c7i.4xlarge"
}

variable "root_volume_gb" {
  description = "Root disk size. A full kernel build with debug info needs ~30 GB."
  type        = number
  default     = 100
}

variable "ubuntu_version" {
  description = "Ubuntu LTS release to boot."
  type        = string
  default     = "26.04"
}

variable "instance_profile_name" {
  description = "Instance profile created by the ../iam stack."
  type        = string
  default     = "kernel-builder-runner"
}

variable "tailscale_auth_key_param" {
  description = "SSM Parameter Store name holding the Tailscale auth key (SecureString)."
  type        = string
  default     = "/kernel-builder/tailscale-auth-key"
}
