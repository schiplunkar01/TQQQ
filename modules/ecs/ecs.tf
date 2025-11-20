data "aws_region" "current" {}

resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-${var.env}-alb-sg"
  description = "ALB SG"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = toset(var.allowed_cidrs)
    content {
      description = "HTTP"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "svc_sg" {
  name        = "${var.project_name}-${var.env}-svc-sg"
  description = "Service SG"
  vpc_id      = var.vpc_id

  ingress {
    description     = "From ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "alb" {
  name               = "${var.project_name}-${var.env}-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.public_subnet_ids
}

resource "aws_lb_target_group" "tg" {
  name         = "${var.project_name}-${var.env}-tg-ip"
  port         = var.container_port
  protocol     = "HTTP"
  vpc_id       = var.vpc_id
  target_type  = "ip"

  health_check {
    path    = var.health_check_path
    matcher = "200-399"
  }

  lifecycle { create_before_destroy = true }
}

# HTTPS listener (toggle)
resource "aws_lb_listener" "https" {
  count             = var.use_https ? 1 : 0
  load_balancer_arn = aws_lb.alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# HTTP listener (toggle)
resource "aws_lb_listener" "http" {
  count             = var.use_https ? 0 : 1
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# Associate WAF
resource "aws_wafv2_web_acl_association" "assoc" {
  resource_arn = aws_lb.alb.arn
  web_acl_arn  = var.waf_acl_arn
}

# CloudWatch log group (no KMS for simplicity)
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project_name}-${var.env}"
  retention_in_days = 14
}

# IAM roles for ECS task
resource "aws_iam_role" "task_exec" {
  name = "${var.project_name}-${var.env}-task-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_exec_cw" {
  role       = aws_iam_role.task_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task_role" {
  name = "${var.project_name}-${var.env}-task-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_ecs_cluster" "this" {
  name = "${var.project_name}-${var.env}-cluster"
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-${var.env}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.task_exec.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([{
    name      = "app"
    image     = var.container_image
    essential = true
    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app.name
        awslogs-region        = data.aws_region.current.name
        awslogs-stream-prefix = "ecs"
      }
    }
    environment = [
      { name = "S3_BUCKET", value = var.s3_bucket_name }
    ]
  }])

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
}

resource "aws_ecs_service" "svc" {
  name            = "${var.project_name}-${var.env}-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.private_subnet_ids
    security_groups = [aws_security_group.svc_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tg.arn
    container_name   = "app"
    container_port   = var.container_port
  }

  depends_on = [aws_lb_listener.http, aws_lb_listener.https]
}
