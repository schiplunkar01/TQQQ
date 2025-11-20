output "alb_dns_name" {
  value = aws_lb.alb.dns_name
}
output "cluster_name" {
  value = aws_ecs_cluster.this.name
}
output "service_name" {
  value = aws_ecs_service.svc.name
}
