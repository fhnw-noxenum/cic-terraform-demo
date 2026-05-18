# envs/prod/backend.tf

terraform {
  backend "s3" {
    bucket         = "tfstate-ml-platform-CHANGEME"      # ← from bootstrap output
    key            = "envs/prod/terraform.tfstate"       # different key from dev
    region         = "eu-central-1"
    dynamodb_table = "terraform-state-lock-ml-platform"
    encrypt        = true
  }
}
