terraform {
  required_version = ">= 1.13.0"

  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }

    aws = {
      source  = "hashicorp/aws"
      version = "6.52.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
