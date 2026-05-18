# envs/dev/variables.tf

variable "aws_region" {
  description = "AWS region for this environment."
  type        = string
  default     = "eu-central-1"
}

variable "account_short_name" {
  description = "Short, S3-safe name for your AWS account, used in bucket names. Buckets are globally unique."
  type        = string
  # No default — must be set in dev.tfvars to avoid collisions.
}

variable "image_uri" {
  description = "Container image URI to deploy. Default = public placeholder until you push your first build."
  type        = string
  default     = "public.ecr.aws/nginx/nginx:1.27-alpine"
}
