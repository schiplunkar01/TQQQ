output "aurora_endpoint" {
  value = aws_rds_cluster.this.endpoint
}
output "db_sg_id" {
  value = aws_security_group.db.id
}
