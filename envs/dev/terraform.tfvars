# envs/dev/terraform.tfvars
#
# Terraform loads this file automatically on plan/apply — no -var-file needed.
# No secrets here.

# ← CHANGE THIS. Must be unique among everyone sharing the AWS account.
#   Use the same name in your `terraform init -backend-config="key=students/<name>/dev.tfstate"`.
student = ""

aws_region = "eu-central-1"

# Until you've built and pushed your own image, the default (a public nginx
# placeholder) is deployed. After `app/build-and-push.sh v1`, uncomment:
# image_uri = "<account-id>.dkr.ecr.eu-central-1.amazonaws.com/<student>-inference-api:v1"
