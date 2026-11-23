# envs/prod/backend.tf
#
# Prod is instructor-only. Fixed key, separate from every student's dev state.

terraform {
  backend "s3" {
    bucket       = "tfstate-ml-platform-REPLACE_WITH_ACCOUNT_ID" # ← from bootstrap output
    key          = "envs/prod/terraform.tfstate"
    region       = "eu-central-1"
    use_lockfile = true
    encrypt      = true
  }
}
