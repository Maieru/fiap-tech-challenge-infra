data "terraform_remote_state" "bootstrap" {
  backend = "s3"

  config = {
    bucket = "fiap-s3-terraform-backend"
    key    = "terraform/bootstrap/terraform.tfstate"
    region = "us-east-1"
  }
}
