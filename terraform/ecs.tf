resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  tags = { Name = "${var.project_name}-cluster" }
}

resource "aws_ecs_task_definition" "main" {
  family                   = var.project_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    # ── Fluent Bit sidecar (FireLens log router) ──────────────────────────────
    {
      name      = "fluent-bit"
      image     = "amazon/aws-for-fluent-bit:latest"
      essential = true

      firelensConfiguration = {
        type = "fluentbit"
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/${var.project_name}/fluent-bit"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "fluent-bit"
        }
      }
    },

    # ── Main application container ────────────────────────────────────────────
    {
      name      = var.project_name
      image     = var.container_image
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      # Logs are routed via Fluent Bit (FireLens) to CloudWatch
      logConfiguration = {
        logDriver = "awsfirelens"
        options = {
          Name              = "cloudwatch_logs"
          region            = var.aws_region
          log_group_name    = "/ecs/${var.project_name}"
          log_stream_prefix = "app"
          auto_create_group = "false"
        }
      }

      dependsOn = [
        {
          containerName = "fluent-bit"
          condition     = "START"
        }
      ]
    }
  ])

  tags = { Name = "${var.project_name}-task" }
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 7

  tags = { Name = "${var.project_name}-logs" }
}

resource "aws_cloudwatch_log_group" "fluent_bit" {
  name              = "/ecs/${var.project_name}/fluent-bit"
  retention_in_days = 7

  tags = { Name = "${var.project_name}-fluent-bit-logs" }
}

resource "aws_ecs_service" "main" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_name   = var.project_name
    container_port   = var.container_port
  }

  depends_on = [aws_lb_listener.http]

  tags = { Name = "${var.project_name}-service" }
}
