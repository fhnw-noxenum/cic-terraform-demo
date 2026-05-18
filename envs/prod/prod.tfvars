# envs/prod/prod.tfvars
#
# Production values. image_tag is NOT set here — CI pins it on each apply.

aws_region         = "eu-central-1"
account_short_name = "acme"
