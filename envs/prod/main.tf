# envs/prod/main.tf
#
# Prod. Same module as dev, different inputs:
# - Larger task size (1 vCPU, 2 GB)
# - 2 tasks minimum, autoscaling to 8 on CPU
# - 3 NAT gateways (one per AZ, no SPOF)
# - 30-day log retention
# - Container Insights enabled
# - Image is pulled from ECR (no public placeholder)
#
# Note the data source pattern: prod LOOKS UP resources created by dev
# (the ECR repo, since image registries are shared across environments).
#
# INSTRUCTOR ONLY. Students stay in envs/dev. This costs ~$190/month.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "prod"
      Project     = "cloud-services-le3"
      Owner       = "data-team"
      ManagedBy   = "terraform"
      Repo        = "github.com/acme/ml-platform"
      Compliance  = "pii-no" # one-flag tag for downstream policies
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  env = "prod"
}

# ---------------------------------------------------------------------------
# Network — production VPC with HA NAT.
# ---------------------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${local.env}-vpc"
  cidr = "10.30.0.0/16" # different CIDR than dev — no overlap

  azs             = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  public_subnets  = ["10.30.101.0/24", "10.30.102.0/24", "10.30.103.0/24"]
  private_subnets = ["10.30.1.0/24", "10.30.2.0/24", "10.30.3.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = false # one NAT per AZ — no SPOF
  one_nat_gateway_per_az = true
  enable_dns_hostnames   = true

  # Flow logs to CloudWatch — useful for security investigations.
  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_max_aggregation_interval    = 60
}

# ---------------------------------------------------------------------------
# ECR — look up the repo created by the dev env.
# Image registries are shared across environments; same image flows through.
# ---------------------------------------------------------------------------

data "aws_ecr_repository" "app" {
  name = "${var.student}-inference-api" # created by envs/dev with the same student name
}

# ---------------------------------------------------------------------------
# S3 — prod model bucket. Versioning + lifecycle for cost control.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "models" {
  bucket = "${var.student}-${local.env}-models-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "models" {
  bucket = aws_s3_bucket.models.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "models" {
  bucket = aws_s3_bucket.models.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "models" {
  bucket                  = aws_s3_bucket.models.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Tier old versions to cheaper storage; expire after a year.
resource "aws_s3_bucket_lifecycle_configuration" "models" {
  bucket = aws_s3_bucket.models.id

  rule {
    id     = "tier-and-expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

# ---------------------------------------------------------------------------
# Secrets — example: an API key the app needs at runtime.
# Created here, value populated outside Terraform (rotate quarterly).
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "third_party_api_key" {
  name                    = "${local.env}/${var.student}-inference-api/third-party-key"
  description             = "API key for the upstream model registry"
  recovery_window_in_days = 30
}

# ---------------------------------------------------------------------------
# The inference API — production sizing.
# ---------------------------------------------------------------------------

module "api" {
  source = "../../modules/ecs-service"

  environment  = local.env
  service_name = "${var.student}-api"

  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnets
  private_subnet_ids = module.vpc.private_subnets

  image          = "${data.aws_ecr_repository.app.repository_url}:${var.image_tag}"
  container_port = 8080

  # Bigger box.
  cpu           = 1024 # 1 vCPU
  memory        = 2048 # 2 GiB
  desired_count = 2    # always-on baseline
  max_count     = 8    # scales up under load

  enable_autoscaling        = true
  enable_container_insights = true
  log_retention_days        = 30

  # Slow LB deregistration — let in-flight requests finish.
  deregistration_delay = 60

  # Container-level health check so a wedged process gets restarted even if
  # the ALB hasn't yet decided it's unhealthy.
  container_health_check_cmd = [
    "CMD-SHELL",
    "curl -f http://localhost:8080/health || exit 1"
  ]

  model_bucket_name = aws_s3_bucket.models.bucket

  env_vars = {
    ENV          = local.env
    LOG_LEVEL    = "INFO"
    MODEL_BUCKET = aws_s3_bucket.models.bucket
  }

  # Injected as an env var at container start. The module grants the ECS
  # execution role read access to exactly these secrets.
  # NOTE: the secret needs a value before tasks can start:
  #   aws secretsmanager put-secret-value --secret-id <name> --secret-string '...'
  secret_arns = {
    THIRD_PARTY_API_KEY = aws_secretsmanager_secret.third_party_api_key.arn
  }
}

# ---------------------------------------------------------------------------
# Alarms — wake up on-call when the service is unhealthy.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "high_5xx" {
  alarm_name          = "${local.env}-${var.student}-api-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  period              = 60
  threshold           = 10
  statistic           = "Sum"

  metric_name = "HTTPCode_Target_5XX_Count"
  namespace   = "AWS/ApplicationELB"

  dimensions = {
    LoadBalancer = module.api.alb_arn_suffix # CloudWatch wants "app/<name>/<id>", not the full ARN
  }

  alarm_description = "More than 10 5xx errors per minute from inference-api"
  # alarm_actions   = [aws_sns_topic.alerts.arn]   # wire to PagerDuty in real prod
}
