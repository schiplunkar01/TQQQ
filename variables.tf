variable "project_name" {
  type    = string
  default = "secscan-minimal"
}

variable "env" {
  type    = string
  default = "dev"
}

variable "aws_region" {
  type    = string
  default = "us-east-2"
}

variable "vpc_cidr" {
  type    = string
  default = "10.40.0.0/16"
}

variable "allowed_cidrs" {
  description = "CIDR blocks allowed to the ALB"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "db_instance_class" {
  type    = string
  default = "db.r6g.large"
}

variable "db_engine_version" {
  type    = string
  default = "14.11"
}

variable "acm_certificate_arn" {
  type        = string
  description = "Ignored when use_https = false"
  default     = ""
}

variable "container_image" {
  type    = string
  default = "public.ecr.aws/nginx/nginx:latest"
}

variable "container_port" {
  type    = number
  default = 80
}

variable "enable_object_lock" {
  type    = bool
  default = true
}

variable "use_https" {
  type    = bool
  default = false
}

variable "health_check_path" {
  type    = string
  default = "/"
}

variable "nat_strategy" {
  type    = string
  default = "single"
  validation {
    condition     = contains(["per_az","single"], var.nat_strategy)
    error_message = "nat_strategy must be one of: per_az, single"
  }
}
