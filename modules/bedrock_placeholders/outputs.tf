output "bedrock_agent_role_arn" {
  value = aws_iam_role.bedrock_agent.arn
}
output "bedrock_kb_role_arn" {
  value = aws_iam_role.bedrock_kb.arn
}
