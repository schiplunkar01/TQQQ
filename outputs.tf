output "alb_dns_name" {
  value = module.ecs.alb_dns_name
}
output "s3_bucket_name" {
  value = module.s3.bucket_name
}
output "aurora_endpoint" {
  value = module.rds.aurora_endpoint
}
output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}
output "ecs_service_name" {
  value = module.ecs.service_name
}
