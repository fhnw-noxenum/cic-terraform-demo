# envs/dev/variables.tf

variable "student" {
  description = "Your short name. Prefixes every resource name so several students can share one AWS account."
  type        = string

  # Lowercase, 2-12 chars: AWS caps load balancer / target group names at
  # 32 characters, and this ends up in "dev-<student>-api-...".
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,11}$", var.student))
    error_message = "Set student in envs/dev/terraform.tfvars: 2-12 chars, lowercase letters and digits, starting with a letter (e.g. \"anna\" or \"amueller\")."
  }
}

variable "aws_region" {
  description = "AWS region for this environment."
  type        = string
  default     = "eu-central-1"
}

variable "image_uri" {
  description = "Container image URI to deploy. Leave null to use a public nginx placeholder until you push your own build."
  type        = string
  default     = null
}
