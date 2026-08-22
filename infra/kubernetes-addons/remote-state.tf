data "terraform_remote_state" "aws_resources" {
  backend = "s3"

  config = {
    bucket = "fiap-s3-terraform-backend"
    key    = "terraform/aws-resources/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "database" {
  backend = "s3"

  config = {
    bucket = "fiap-s3-terraform-backend"
    key    = "terraform/database/terraform.tfstate"
    region = "us-east-1"
  }
}
