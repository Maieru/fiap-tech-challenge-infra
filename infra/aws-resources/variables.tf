variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "jwt_signing_key" {
  type      = string
  sensitive = true
}

variable "create_eks_instance" {
  type    = bool
  default = true
}