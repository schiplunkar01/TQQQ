resource "aws_s3_bucket" "docs" {
  bucket              = "${var.project_name}-docs"
  force_destroy       = false
  object_lock_enabled = var.enable_object_lock
  tags = { Purpose = "security-scan-docs" }
}

resource "aws_s3_bucket_versioning" "docs" {
  bucket = aws_s3_bucket.docs.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "docs" {
  bucket = aws_s3_bucket.docs.id
  rule { apply_server_side_encryption_by_default { sse_algorithm = "aws:kms" } }
}

resource "aws_s3_bucket_public_access_block" "docs" {
  bucket                  = aws_s3_bucket.docs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "docs" {
  bucket = aws_s3_bucket.docs.id
  rule {
    id     = "expire-mpu"
    status = "Enabled"
    filter { prefix = "" }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

resource "aws_s3_object" "prefixes" {
  for_each = toset(["raw/", "kb/", "exports/"])
  bucket   = aws_s3_bucket.docs.id
  key      = each.value
  content  = ""
}
