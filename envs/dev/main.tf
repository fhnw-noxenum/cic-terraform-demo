# envs/dev/main.tf
#
# The dev environment. Small, single-AZ-NAT, no autoscaling.
# About 30 lines of composition — the heavy lifting lives in the modules.

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Tags applied to EVERY resource this provider creates.
  # This is how cost allocation actually works.
  default_tags {
    tags = {
      Environment = "dev"
      Project     = "cloud-services-le3"
      Owner       = "data-team"
      ManagedBy   = "terraform"
      Repo        = "github.com/acme/ml-platform"
    }
  }
}

locals {
  env = "dev"
}

# ---------------------------------------------------------------------------
# Network — VPC + 2 AZs of public/private subnets + 1 NAT (dev = cheap).
# Uses the official AWS module from the registry.
# ---------------------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "${local.env}-vpc"
  cidr = "10.20.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  public_subnets  = ["10.20.101.0/24", "10.20.102.0/24"]
  private_subnets = ["10.20.1.0/24",   "10.20.2.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true   # one NAT for the whole VPC — saves ~$32/mo
  enable_dns_hostnames = true
}

# ---------------------------------------------------------------------------
# ECR repository — stores the container image.
# Same image gets promoted dev → staging → prod, so the repo is per-project,
# not per-environment. We define it here only because dev is the lowest env.
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "app" {
  name                 = "inference-api"
  image_tag_mutability = "IMMUTABLE"   # once tagged, can't be overwritten

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
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "models" {
  bucket = "${var.account_short_name}-${local.env}-models"
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
  service_name = "inference-api"

  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnets
  private_subnet_ids = module.vpc.private_subnets

  # Until the first image is pushed, use a public placeholder.
  # After the first push, swap to: "${aws_ecr_repository.app.repository_url}:v1"
  image          = var.image_uri
  container_port = 8080

  cpu           = 256      # 0.25 vCPU — dev is cheap
  memory        = 512
  desired_count = 1        # single task in dev

  enable_autoscaling = false
  log_retention_days = 7

  # Give the task read access to the models bucket via its task role.
  model_bucket_arn = aws_s3_bucket.models.arn

  env_vars = {
    ENV          = local.env
    LOG_LEVEL    = "DEBUG"
    MODEL_BUCKET = aws_s3_bucket.models.id
  }
}
