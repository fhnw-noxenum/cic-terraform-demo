# envs/prod/outputs.tf

output "api_url" {
  description = "The prod API URL."
  value       = "http://${module.api.alb_dns_name}"
}

output "alb_dns_name" {
  description = "ALB DNS name — point your Route 53 CNAME here."
  value       = module.api.alb_dns_name
}

output "model_bucket" {
  description = "Prod model bucket."
  value       = aws_s3_bucket.models.id
}

output "log_group" {
  description = "Tail prod logs."
  value       = module.api.log_group_name
}
