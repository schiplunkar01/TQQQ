data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  root_arn   = "arn:${data.aws_partition.current.partition}:iam::${local.account_id}:root"
}

resource "aws_kms_key" "rds" {
  description             = "KMS key for RDS at rest"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid      = "EnableIAMUserPermissions",
      Effect   = "Allow",
      Principal= { AWS = local.root_arn },
      Action   = "kms:*",
      Resource = "*"
    }]
  })
}

resource "aws_kms_key" "logs" {
  description             = "KMS key for CloudWatch Logs encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid      = "EnableIAMUserPermissions",
        Effect   = "Allow",
        Principal= { AWS = local.root_arn },
        Action   = "kms:*",
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchLogsUse",
        Effect = "Allow",
        Principal = { Service = "logs.${local.region}.amazonaws.com" },
        Action = ["kms:Encrypt","kms:Decrypt","kms:ReEncrypt*","kms:GenerateDataKey*","kms:DescribeKey"],
        Resource = "*",
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:${data.aws_partition.current.partition}:logs:${local.region}:${local.account_id}:log-group:*"
          }
        }
      }
    ]
  })
}
