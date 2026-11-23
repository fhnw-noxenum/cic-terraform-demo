# bootstrap/outputs.tf
#
# Print the value you need to paste into envs/*/backend.tf

output "state_bucket_name" {
  description = "S3 bucket for Terraform state. Paste into envs/*/backend.tf"
  value       = aws_s3_bucket.tfstate.id
}

output "next_steps" {
  description = "What to do next"
  value       = <<-EOT

    State backend is ready.

    Update envs/dev/backend.tf and envs/prod/backend.tf:

        bucket = "${aws_s3_bucket.tfstate.id}"

    Commit that change so every student gets it.

  EOT
}
