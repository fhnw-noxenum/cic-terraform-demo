# modules/ecs-service/main.tf
#
# A reusable module: deploy a containerized HTTP service behind an
# Application Load Balancer, on AWS Fargate.
#
# Inputs: VPC ID, subnets, container image, sizing.
# Outputs: ALB DNS name + the security group, task role ARN.
#
# Same module is used by envs/dev/ AND envs/prod/ with different inputs.
# That's the point of modules.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

locals {
  # Compose a consistent name prefix: "{env}-{service}"
  # Used for every named resource to make things groupable in the console.
  name_prefix = "${var.environment}-${var.service_name}"
}

# ---------------------------------------------------------------------------
# ECS cluster — a logical grouping. Cheap, no per-cluster cost on Fargate.
# ---------------------------------------------------------------------------

resource "aws_ecs_cluster" "this" {
  name = local.name_prefix

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }
}

# ---------------------------------------------------------------------------
# CloudWatch log group — ECS streams container stdout/stderr here.
# Retention is short for dev (cost), longer for prod (compliance).
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = var.log_retention_days
}

# ---------------------------------------------------------------------------
# Security groups — the principle is "two SGs, ALB → tasks".
# Internet talks to the ALB. The ALB talks to the tasks. Nothing else can.
# ---------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb"
  description = "Allow HTTP/HTTPS from the internet to the ALB"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # NOTE: in real prod you would terminate TLS here and remove port 80.
  # Keeping HTTP-only to make the demo work without a domain + ACM cert.

  egress {
    description = "All outbound (to tasks)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "tasks" {
  name        = "${local.name_prefix}-tasks"
  description = "Allow traffic from the ALB only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "From the ALB on the container port"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id] # not a CIDR, an SG reference
  }

  egress {
    description = "All outbound, needed to pull images, reach APIs, etc."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------------------------------------------------------------------
# Application Load Balancer
# ---------------------------------------------------------------------------

resource "aws_lb" "this" {
  name               = local.name_prefix
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  # In real prod: enable access logs to S3.
  # In a classroom demo: skip it — fewer moving parts.
}

resource "aws_lb_target_group" "this" {
  name        = local.name_prefix
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # Fargate uses ENI IPs, not instance IDs

  health_check {
    path                = var.health_check_path
    matcher             = "200-299"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  # Drain quickly in dev for fast iteration; slow in prod for safety.
  deregistration_delay = var.deregistration_delay
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

# ---------------------------------------------------------------------------
# IAM — the two roles every ECS task needs.
# ---------------------------------------------------------------------------

# Execution role: used by ECS itself, to pull the image and write logs.
resource "aws_iam_role" "execution" {
  name               = "${local.name_prefix}-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task role: used by YOUR application code at runtime.
# Whatever permissions you grant here = what your code can call.
# Principle of least privilege applies.
resource "aws_iam_role" "task" {
  name               = "${local.name_prefix}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

# Secrets in the container definition are fetched by ECS itself at startup,
# so the EXECUTION role (not the task role) needs to read them.
resource "aws_iam_role_policy" "execution_secrets" {
  count = length(var.secret_arns) > 0 ? 1 : 0

  name = "${local.name_prefix}-read-secrets"
  role = aws_iam_role.execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = values(var.secret_arns)
    }]
  })
}

# Optional: read-only access to the model bucket for the application code.
# Pass the bucket NAME (known at plan time) rather than its ARN — the ARN of a
# bucket that doesn't exist yet is unknown at plan time, and `count` can't
# depend on unknown values.
resource "aws_iam_role_policy" "task_model_bucket" {
  count = var.model_bucket_name == "" ? 0 : 1

  name = "${local.name_prefix}-read-models"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = "arn:aws:s3:::${var.model_bucket_name}"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "arn:aws:s3:::${var.model_bucket_name}/*"
      },
    ]
  })
}

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# ---------------------------------------------------------------------------
# Task definition — describes the container(s) to run.
# ---------------------------------------------------------------------------

resource "aws_ecs_task_definition" "this" {
  family                   = local.name_prefix
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory

  execution_role_arn = aws_iam_role.execution.arn
  task_role_arn      = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = var.service_name
    image     = var.image
    essential = true

    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]

    # Environment variables — non-secret config goes here.
    environment = [
      for k, v in var.env_vars : { name = k, value = v }
    ]

    # Secrets fetched from Secrets Manager at startup — never in env vars
    # at the .tf level, never baked into the image.
    secrets = [
      for k, v in var.secret_arns : { name = k, valueFrom = v }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.this.name
        awslogs-region        = data.aws_region.current.region
        awslogs-stream-prefix = "ecs"
      }
    }

    # Container-level health check — independent of the ALB.
    # Useful if your image has curl or wget. Some slim images don't.
    healthCheck = var.container_health_check_cmd == null ? null : {
      command     = var.container_health_check_cmd
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 10
    }
  }])
}

data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# ECS service — the desired state: "run N copies of this task, behind that
# load balancer, in those subnets".
# ---------------------------------------------------------------------------

resource "aws_ecs_service" "this" {
  name            = local.name_prefix
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = false # tasks in private subnets
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = var.service_name
    container_port   = var.container_port
  }

  # Terraform owns the image tag here: change `image`, apply, and ECS rolls
  # out a new task definition. (If a separate CD tool deployed images, you
  # would add lifecycle { ignore_changes = [task_definition] } so the two
  # don't fight — but then Terraform image changes stop taking effect.)

  # Wait for ALB target group to exist before starting tasks.
  depends_on = [aws_lb_listener.http]
}

# ---------------------------------------------------------------------------
# Autoscaling — optional, controlled by enable_autoscaling.
# ---------------------------------------------------------------------------

resource "aws_appautoscaling_target" "this" {
  count = var.enable_autoscaling ? 1 : 0

  max_capacity       = var.max_count
  min_capacity       = var.desired_count
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  count = var.enable_autoscaling ? 1 : 0

  name               = "${local.name_prefix}-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this[0].resource_id
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 60.0

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
