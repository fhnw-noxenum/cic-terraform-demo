# modules/ecs-service/variables.tf
#
# Every variable has a description, a type, and a sensible default where
# possible. This is the module's public interface — treat it like an API.

# ---------------------------------------------------------------------------
# Required: who and where
# ---------------------------------------------------------------------------

variable "environment" {
  description = "Environment name — dev, staging, prod. Used as a name prefix."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "service_name" {
  description = "Short service identifier, e.g. 'inference-api'. Goes into all resource names."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to deploy into."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs — the ALB lives here. At least 2 for HA."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "ALB requires at least 2 subnets in 2 AZs."
  }
}

variable "private_subnet_ids" {
  description = "Private subnet IDs — the Fargate tasks live here."
  type        = list(string)
}

# ---------------------------------------------------------------------------
# Container
# ---------------------------------------------------------------------------

variable "image" {
  description = "Full container image URI, e.g. 1234.dkr.ecr.eu-central-1.amazonaws.com/inference-api:v1.2"
  type        = string
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 8080
}

variable "env_vars" {
  description = "Plain-text environment variables for the container. NOT for secrets."
  type        = map(string)
  default     = {}
}

variable "secret_arns" {
  description = "Map of ENV_VAR_NAME → Secrets Manager / Parameter Store ARN. Injected at startup."
  type        = map(string)
  default     = {}
}

variable "container_health_check_cmd" {
  description = "Container-level healthcheck command, e.g. ['CMD-SHELL', 'curl -f http://localhost:8080/health || exit 1']. Null disables."
  type        = list(string)
  default     = null
}

# ---------------------------------------------------------------------------
# Sizing
# ---------------------------------------------------------------------------

variable "cpu" {
  description = "Task CPU units. 256 = 0.25 vCPU, 1024 = 1 vCPU. Must be a valid Fargate combo with memory."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Task memory in MiB. 512, 1024, 2048..."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of tasks to run. Also the minimum when autoscaling is enabled."
  type        = number
  default     = 1
}

variable "max_count" {
  description = "Maximum number of tasks when autoscaling is enabled."
  type        = number
  default     = 4
}

variable "enable_autoscaling" {
  description = "Whether to attach CPU-based autoscaling. Recommended for prod."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Load balancer
# ---------------------------------------------------------------------------

variable "health_check_path" {
  description = "ALB health check path on the container."
  type        = string
  default     = "/health"
}

variable "deregistration_delay" {
  description = "Seconds to wait before removing a task from the LB. 5 in dev (fast deploys), 30+ in prod (drain connections)."
  type        = number
  default     = 30
}

# ---------------------------------------------------------------------------
# Observability and IAM
# ---------------------------------------------------------------------------

variable "log_retention_days" {
  description = "CloudWatch log retention. 7 in dev, 30-90 in prod."
  type        = number
  default     = 7
}

variable "enable_container_insights" {
  description = "Detailed per-container CPU/memory metrics. Costs ~$2/cluster/month."
  type        = bool
  default     = false
}

variable "model_bucket_name" {
  description = "Optional: S3 bucket name the task role gets read-only access to. Empty string = no policy."
  type        = string
  default     = ""
}
