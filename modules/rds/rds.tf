resource "aws_db_subnet_group" "this" {
  name       = "${var.project_name}-${var.env}-db-subnets"
  subnet_ids = var.private_subnet_ids
}

resource "aws_security_group" "db" {
  name        = "${var.project_name}-${var.env}-db-sg"
  description = "DB SG"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_rds_cluster_parameter_group" "pg" {
  name   = "${var.project_name}-${var.env}-pg14"
  family = "aurora-postgresql14"
}

resource "aws_rds_cluster" "this" {
  cluster_identifier     = "${var.project_name}-${var.env}-cluster"
  engine                 = "aurora-postgresql"
  engine_version         = var.db_engine_version
  master_username        = "appadmin"
  master_password        = "ChangeMe1234!"
  kms_key_id             = var.kms_key_arn
  storage_encrypted      = true
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  apply_immediately      = true
  skip_final_snapshot    = true

  depends_on = [aws_rds_cluster_parameter_group.pg]
}

resource "aws_rds_cluster_instance" "instances" {
  count                = 2
  identifier           = "${var.project_name}-${var.env}-db-${count.index}"
  cluster_identifier   = aws_rds_cluster.this.id
  instance_class       = var.db_instance_class
  engine               = "aurora-postgresql"
  engine_version       = var.db_engine_version
  publicly_accessible  = false
  db_subnet_group_name = aws_db_subnet_group.this.name
}
