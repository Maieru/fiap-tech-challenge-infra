terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.52.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
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

provider "helm" {
  kubernetes {
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
}
