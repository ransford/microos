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
  description = "Project tag, shared with the other stacks."
  type        = string
  default     = "kernel-builder"
}

variable "repository_name" {
  description = "ECR repository for VM images. Must match ecr_repository in ../iam."
  type        = string
  default     = "microos"
}

variable "keep_images" {
  description = "How many images to keep before ECR expires the oldest."
  type        = number
  default     = 10
}
