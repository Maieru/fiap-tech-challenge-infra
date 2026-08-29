data "terraform_remote_state" "aws_resources" {
  backend = "s3"

  config = {
    bucket = "fiap-s3-terraform-backend"
    key    = "terraform/aws-resources/terraform.tfstate"
    region = var.aws_region
  }
}

data "terraform_remote_state" "database" {
  backend = "s3"

  config = {
    bucket = "fiap-s3-terraform-backend"
    key    = "terraform/database/terraform.tfstate"
    region = var.aws_region
  }
}

data "terraform_remote_state" "api_gateway" {
  backend = "s3"

  config = {
    bucket = "fiap-s3-terraform-backend"
    key    = "terraform/api-gateway/terraform.tfstate"
    region = var.aws_region
  }
}
