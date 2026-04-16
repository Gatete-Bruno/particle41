data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# ── Execution role (used by ECS agent to pull images and write logs) ──────────

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${var.project_name}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = { Name = "${var.project_name}-execution-role" }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ── Task role (used by containers at runtime — Fluent Bit needs CloudWatch) ───

resource "aws_iam_role" "ecs_task" {
  name               = "${var.project_name}-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = { Name = "${var.project_name}-task-role" }
}

resource "aws_iam_role_policy_attachment" "ecs_task_cloudwatch" {
  role       = aws_iam_role.ecs_task.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}
