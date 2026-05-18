# modules/ecs-service/outputs.tf

output "alb_dns_name" {
  description = "Public DNS name of the ALB. curl http://<this>/health to test."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "ALB's Route 53 zone ID — use this when creating an alias record."
  value       = aws_lb.this.zone_id
}

output "alb_arn" {
  description = "ALB ARN — pass to a WAFv2 web ACL association if you add one."
  value       = aws_lb.this.arn
}

output "service_name" {
  description = "ECS service name — useful for deploy tooling."
  value       = aws_ecs_service.this.name
}

output "cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

output "task_role_arn" {
  description = "Task role ARN — attach extra policies to this from the env code."
  value       = aws_iam_role.task.arn
}

output "task_role_name" {
  description = "Task role name — for use with aws_iam_role_policy_attachment."
  value       = aws_iam_role.task.name
}

output "log_group_name" {
  description = "CloudWatch log group. Useful for setting up metric filters or alarms."
  value       = aws_cloudwatch_log_group.this.name
}
