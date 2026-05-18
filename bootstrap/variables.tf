# bootstrap/variables.tf

variable "aws_region" {
  description = "AWS region for the state backend. Pick one and never change it."
  type        = string
  default     = "eu-central-1"
}

variable "project" {
  description = "Short project identifier — used in bucket and table names."
  type        = string
  default     = "ml-platform"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.project))
    error_message = "Project must be lowercase, start with a letter, 3-30 chars, alphanumerics and hyphens only."
  }
}
