# envs/dev/outputs.tf

output "api_url" {
  description = "The dev API URL. Test with: curl $(terraform output -raw api_url)/health"
  value       = "http://${module.api.alb_dns_name}"
}

output "ecr_repository_url" {
  description = "Push images here: docker push <this>:v1"
  value       = aws_ecr_repository.app.repository_url
}

output "model_bucket" {
  description = "S3 bucket for model artifacts."
  value       = aws_s3_bucket.models.id
}

output "log_group" {
  description = "Tail logs with: aws logs tail <this> --follow"
  value       = module.api.log_group_name
}
