module "network" {
  source       = "./modules/network"
  vpc_cidr     = var.vpc_cidr
  nat_strategy = var.nat_strategy
}

module "security" {
  source       = "./modules/security"
  project_name = var.project_name
  env          = var.env
}

module "s3" {
  source             = "./modules/s3"
  project_name       = var.project_name
  enable_object_lock = var.enable_object_lock
}

module "rds" {
  source              = "./modules/rds"
  project_name        = var.project_name
  env                 = var.env
  vpc_id              = module.network.vpc_id
  private_subnet_ids  = module.network.private_subnet_ids
  db_instance_class   = var.db_instance_class
  db_engine_version   = var.db_engine_version
  kms_key_arn         = module.security.kms_rds_key_arn
}

module "ecs" {
  source               = "./modules/ecs"
  project_name         = var.project_name
  env                  = var.env
  vpc_id               = module.network.vpc_id
  public_subnet_ids    = module.network.public_subnet_ids
  private_subnet_ids   = module.network.private_subnet_ids
  allowed_cidrs        = var.allowed_cidrs
  acm_certificate_arn  = var.acm_certificate_arn
  container_image      = var.container_image
  container_port       = var.container_port
  s3_bucket_name       = module.s3.bucket_name
  rds_sg_id            = module.rds.db_sg_id
  kms_logs_key_arn     = module.security.kms_logs_key_arn
  waf_acl_arn          = module.security.waf_acl_arn
  use_https            = var.use_https
  health_check_path    = var.health_check_path
}

module "events" {
  source       = "./modules/events"
  project_name = var.project_name
  env          = var.env
}

module "bedrock_placeholders" {
  source         = "./modules/bedrock_placeholders"
  project_name   = var.project_name
  env            = var.env
  s3_bucket_name = module.s3.bucket_name
  s3_kb_prefix   = "kb/"
}
