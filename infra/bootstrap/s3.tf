resource "aws_s3_bucket" "s3-terraform-backend" {
  bucket        = "fiap-s3-terraform-backend"
  force_destroy = false
  lifecycle { prevent_destroy = true }
  tags = { Name = "FIAP Terraform Backend Bucket", Project = "fiap-tech-challenge" }
}
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.s3-terraform-backend.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.s3-terraform-backend.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.s3-terraform-backend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.s3-terraform-backend.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Deny", Principal = "*", Action = "s3:*"
    Resource  = [aws_s3_bucket.s3-terraform-backend.arn, "${aws_s3_bucket.s3-terraform-backend.arn}/*"]
    Condition = { Bool = { "aws:SecureTransport" = "false" } }
  }] })
}
