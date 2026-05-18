# envs/dev/backend.tf
#
# After running bootstrap/, paste the bucket and DynamoDB table names here.
# These can't be variables — Terraform reads them before evaluating anything.

terraform {
  backend "s3" {
    bucket         = "tfstate-ml-platform-682033463765"     # ← from bootstrap output
    key            = "envs/dev/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "terraform-state-lock-ml-platform" # ← from bootstrap output
    encrypt        = true
  }
}
