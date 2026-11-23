# envs/dev/backend.tf
#
# Backend blocks can't use variables — Terraform reads them before evaluating
# anything else. So this is a *partial* configuration:
#
#   bucket — the same for everyone. The instructor pastes it here once, from
#            the bootstrap output.
#   key    — different for every student, so nobody overwrites anyone else's
#            state. Deliberately NOT set here; pass it at init time:
#
#     terraform init -backend-config="key=students/<your-name>/dev.tfstate"
#
#   (If you forget it, `terraform init` asks for it interactively.)

terraform {
  backend "s3" {
    bucket       = "tfstate-ml-platform-REPLACE_WITH_ACCOUNT_ID" # ← from bootstrap output
    region       = "eu-central-1"
    use_lockfile = true # S3-native locking (Terraform >= 1.10), no DynamoDB
    encrypt      = true
  }
}
