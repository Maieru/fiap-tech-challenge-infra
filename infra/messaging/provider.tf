terraform {
  required_providers {
    random     = { source = "hashicorp/random", version = "~> 3.7" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.0" }
  }
}
provider "kubernetes" {
  host                   = data.terraform_remote_state.aws_resources.outputs.eks.endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.aws_resources.outputs.eks.ca)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.aws_resources.outputs.eks.name, "--region", "us-east-1"]
  }
}
data "terraform_remote_state" "aws_resources" {
  backend = "s3"
  config  = { bucket = "fiap-s3-terraform-backend", key = "terraform/aws-resources/terraform.tfstate", region = "us-east-1" }
}
