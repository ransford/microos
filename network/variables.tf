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

variable "instance_type" {
  description = "Instance type the builders will use; the subnets go in an AZ that offers it."
  type        = string
  default     = "c7i.4xlarge"
}

variable "ssh_public_key_path" {
  description = "Public half of the SSH key used to log in as `ubuntu`."
  type        = string
  default     = "~/.ssh/kernel-builder.pub"
}

variable "vpc_cidr" {
  type    = string
  default = "10.42.0.0/16"
}
