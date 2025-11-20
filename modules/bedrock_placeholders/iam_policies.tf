resource "aws_iam_role" "bedrock_agent" {
  name = "${var.project_name}-${var.env}-bedrock-agent"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "bedrock.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "bedrock_agent_inline" {
  name = "${var.project_name}-${var.env}-bedrock-agent-policy"
  role = aws_iam_role.bedrock_agent.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = ["s3:GetObject","s3:ListBucket"], Resource = [
        "arn:aws:s3:::${var.s3_bucket_name}",
        "arn:aws:s3:::${var.s3_bucket_name}/${var.s3_kb_prefix}*"
      ]},
      { Effect = "Allow", Action = ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"], Resource = "*" }
    ]
  })
}

resource "aws_iam_role" "bedrock_kb" {
  name = "${var.project_name}-${var.env}-bedrock-kb"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "bedrock.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "bedrock_kb_inline" {
  name = "${var.project_name}-${var.env}-bedrock-kb-policy"
  role = aws_iam_role.bedrock_kb.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = ["s3:GetObject","s3:ListBucket"], Resource = [
        "arn:aws:s3:::${var.s3_bucket_name}",
        "arn:aws:s3:::${var.s3_bucket_name}/${var.s3_kb_prefix}*"
      ]},
      { Effect = "Allow", Action = ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"], Resource = "*" }
    ]
  })
}
