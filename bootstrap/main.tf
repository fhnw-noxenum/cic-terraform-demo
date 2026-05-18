# bootstrap/main.tf
#
# Chicken-and-egg solution: this stack creates the S3 bucket and DynamoDB
# table that every OTHER stack uses as its remote backend.
#
# It uses LOCAL state itself (no backend "s3" block) — because the S3 bucket
# it manages doesn't exist yet on the first run.
#
# Run this ONCE per AWS account. Then never touch it again.

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Note: NO backend block. Local state by design.
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "cloud-services-le3"
      Stack     = "bootstrap"
      ManagedBy = "terraform"
    }
  }
}

# Account ID is appended to the bucket name to make it globally unique.
data "aws_caller_identity" "current" {}

locals {
  bucket_name = "tfstate-${var.project}-${data.aws_caller_identity.current.account_id}"
}

# ---------------------------------------------------------------------------
# S3 bucket — stores the .tfstate files for every other environment.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "tfstate" {
  bucket = local.bucket_name

  # Don't accidentally delete the state bucket. Lifesaver.
  lifecycle {
    prevent_destroy = true
  }
}

# Versioning — recover from accidental state corruption.
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt the state at rest. State files contain secrets in plain text.
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block ALL public access. There is no reason this bucket should be reachable
# from the internet, and a public state bucket = your infrastructure on a
# silver platter.
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# DynamoDB lock table — prevents two engineers from running apply at the
# same time and corrupting state.
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "tfstate_lock" {
  name         = "terraform-state-lock-${var.project}"
  billing_mode = "PAY_PER_REQUEST"        # cheap; you barely use it
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  lifecycle {
    prevent_destroy = true
  }
}
