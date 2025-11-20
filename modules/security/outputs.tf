output "kms_rds_key_arn" {
  value = aws_kms_key.rds.arn
}
output "kms_logs_key_arn" {
  value = aws_kms_key.logs.arn
}
output "waf_acl_arn" {
  value = aws_wafv2_web_acl.main.arn
}
