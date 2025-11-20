variable "project_name" {
  type = string
}
variable "env" {
  type = string
}
variable "vpc_id" {
  type = string
}
variable "private_subnet_ids" {
  type = list(string)
}
variable "db_instance_class" {
  type = string
}
variable "db_engine_version" {
  type = string
}
variable "kms_key_arn" {
  type = string
}
