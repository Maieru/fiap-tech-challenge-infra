resource "aws_s3_bucket" "s3-terraform-backend" {
  bucket = "fiap-s3-terraform-backend"
  tags = {
    Name = "FIAP Terraform Backend Bucket"
  }
  force_destroy = true
}
