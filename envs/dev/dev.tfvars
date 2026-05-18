# envs/dev/dev.tfvars
#
# Per-environment values. Commit this file (no secrets here).
# Apply with: terraform apply -var-file=dev.tfvars

aws_region         = "eu-central-1"
account_short_name = "acme"   # change to something unique to your account

# Until you've built and pushed an image, the default (public nginx) works
# for the demo — it returns 200 on / so the ALB health check passes.
# After your first push, uncomment:
# image_uri = "1234567890.dkr.ecr.eu-central-1.amazonaws.com/inference-api:v1"
