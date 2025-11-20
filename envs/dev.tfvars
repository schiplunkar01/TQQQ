aws_region        = "us-east-2"
project_name      = "secscan-minimal-yourinitials123"
container_image   = "public.ecr.aws/nginx/nginx:latest"
container_port    = 80
use_https         = false
health_check_path = "/"
nat_strategy      = "single"
allowed_cidrs     = ["0.0.0.0/0"]
