# envs/prod/variables.tf

variable "student" {
  description = "Name prefix. Must match the student name of the dev stack whose ECR repo prod deploys from (e.g. the instructor's own)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,11}$", var.student))
    error_message = "2-12 chars, lowercase letters and digits, starting with a letter."
  }
}

variable "aws_region" {
  description = "AWS region for prod."
  type        = string
  default     = "eu-central-1"
}

variable "image_tag" {
  description = "ECR image tag to deploy. Set by CI on every release."
  type        = string
  # No default — prod must be explicit. CI passes -var "image_tag=v1.2.3".
}
