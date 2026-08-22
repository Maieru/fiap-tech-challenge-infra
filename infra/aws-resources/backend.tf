terraform {
  backend "s3" {
    bucket       = "fiap-s3-terraform-backend"
    key          = "terraform/aws-resources/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
