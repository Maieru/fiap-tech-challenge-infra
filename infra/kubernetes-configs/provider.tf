terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}


provider "kubernetes" {
  host                   = data.terraform_remote_state.aws_resources.outputs.eks.endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.aws_resources.outputs.eks.ca)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      data.terraform_remote_state.aws_resources.outputs.eks.name,
      "--region",
      var.aws_region
    ]
  }
}