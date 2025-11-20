variable "project_name" {
  type = string
}
variable "env" {
  type = string
}
variable "vpc_id" {
  type = string
}
variable "public_subnet_ids" {
  type = list(string)
}
variable "private_subnet_ids" {
  type = list(string)
}
variable "allowed_cidrs" {
  type = list(string)
}
variable "acm_certificate_arn" {
  type = string
}
variable "container_image" {
  type = string
}
variable "container_port" {
  type = number
}
variable "s3_bucket_name" {
  type = string
}
variable "rds_sg_id" {
  type = string
}
variable "kms_logs_key_arn" {
  type = string
}
variable "waf_acl_arn" {
  type = string
}
variable "use_https" {
  type = bool
}
variable "health_check_path" {
  type = string
}
