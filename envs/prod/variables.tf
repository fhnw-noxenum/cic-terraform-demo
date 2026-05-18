# envs/prod/variables.tf

variable "aws_region" {
  description = "AWS region for prod."
  type        = string
  default     = "eu-central-1"
}

variable "account_short_name" {
  description = "Short, S3-safe name for your AWS account, used in bucket names."
  type        = string
}

variable "image_tag" {
  description = "ECR image tag to deploy. Set by CI on every release."
  type        = string
  # No default — prod must be explicit. CI passes -var "image_tag=v1.2.3".
}
