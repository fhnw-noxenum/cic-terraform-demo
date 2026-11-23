# envs/dev/main.tf
#
# The dev environment. Small, single NAT, no autoscaling.
# Mostly composition — the heavy lifting lives in the modules.
#
# Several students share one AWS account, so every name contains var.student.

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

  # Tags applied to EVERY resource this provider creates.
  # This is how cost allocation actually works — filter Cost Explorer or
  # Resource Groups by Owner to see exactly what each student is running.
  default_tags {
    tags = {
      Environment = "dev"
      Project     = "cloud-services-le3"
      Owner       = var.student
      ManagedBy   = "terraform"
      Repo        = "github.com/acme/ml-platform"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  env  = "dev"
  name = "${var.student}-${local.env}" # e.g. "anna-dev"

  # No image pushed yet → run a public placeholder. nginx-unprivileged listens
  # on 8080, same as our FastAPI app, so the port never changes. It has no
  # /health endpoint, though, so the ALB checks "/" until you deploy the app.
  image             = coalesce(var.image_uri, "public.ecr.aws/nginx/nginx-unprivileged:1.27-alpine")
  health_check_path = var.image_uri == null ? "/" : "/health"
}

# ---------------------------------------------------------------------------
# Network — VPC + 2 AZs of public/private subnets + 1 NAT (dev = cheap).
# Uses the official AWS module from the registry.
# ---------------------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${local.name}-vpc"
  cidr = "10.20.0.0/16" # same CIDR for every student is fine: separate VPCs

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  public_subnets  = ["10.20.101.0/24", "10.20.102.0/24"]
  private_subnets = ["10.20.1.0/24", "10.20.2.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true # one NAT for the whole VPC — saves ~$32/mo
  enable_dns_hostnames = true
}

# ---------------------------------------------------------------------------
# ECR repository — stores the container image.
# In a real company the same image gets promoted dev → staging → prod, so the
# repo is per-project, not per-environment. We define it here only because
# dev is the lowest env.
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "app" {
  name                 = "${var.student}-inference-api"
  image_tag_mutability = "IMMUTABLE" # once tagged, can't be overwritten

  # Classroom setting: let `terraform destroy` delete the repo even if it
  # still contains images. Leave this off in real life.
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Auto-expire untagged images after 14 days.
# Without this, ECR storage costs grow forever.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged images older than 14 days"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 14
      }
      action = { type = "expire" }
    }]
  })
}

# ---------------------------------------------------------------------------
# S3 bucket — model artifacts, training data, etc.
# Bucket names are GLOBALLY unique (across all AWS customers), so we append
# the account ID.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "models" {
  bucket = "${local.name}-models-${data.aws_caller_identity.current.account_id}"

  # Classroom setting: allow `terraform destroy` even if you uploaded files.
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "models" {
  bucket = aws_s3_bucket.models.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "models" {
  bucket = aws_s3_bucket.models.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# The inference API — uses the ecs-service module.
# This is where you would change image, count, sizing when promoting.
# ---------------------------------------------------------------------------

module "api" {
  source = "../../modules/ecs-service"

  environment  = local.env
  service_name = "${var.student}-api" # → "dev-<student>-api-..." resource names

  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnets
  private_subnet_ids = module.vpc.private_subnets

  image             = local.image
  container_port    = 8080
  health_check_path = local.health_check_path

  cpu           = 256 # 0.25 vCPU — dev is cheap
  memory        = 512
  desired_count = 1 # single task in dev

  enable_autoscaling   = false
  log_retention_days   = 7
  deregistration_delay = 5 # fast deploys in dev

  # Give the task read-only access to the models bucket via its task role.
  model_bucket_name = aws_s3_bucket.models.bucket

  env_vars = {
    ENV          = local.env
    LOG_LEVEL    = "DEBUG"
    MODEL_BUCKET = aws_s3_bucket.models.bucket
  }
}
