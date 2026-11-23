# envs/prod/terraform.tfvars
#
# Production values, loaded automatically. image_tag is NOT set here — CI pins
# it on each apply: terraform apply -var "image_tag=v1.2.3"

student    = "teacher" # instructor's dev stack provides the ECR repo
aws_region = "eu-central-1"
