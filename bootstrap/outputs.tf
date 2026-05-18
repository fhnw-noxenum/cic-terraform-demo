# bootstrap/outputs.tf
#
# Print the values you need to paste into envs/*/backend.tf

output "state_bucket_name" {
  description = "S3 bucket for Terraform state. Paste into envs/*/backend.tf"
  value       = aws_s3_bucket.tfstate.id
}

output "lock_table_name" {
  description = "DynamoDB table for state locking. Paste into envs/*/backend.tf"
  value       = aws_dynamodb_table.tfstate_lock.name
}

output "next_steps" {
  description = "What to do next"
  value       = <<-EOT

    State backend is ready.

    Update envs/dev/backend.tf and envs/prod/backend.tf:

        bucket         = "${aws_s3_bucket.tfstate.id}"
        dynamodb_table = "${aws_dynamodb_table.tfstate_lock.name}"

    Then:  cd ../envs/dev && terraform init

  EOT
}
