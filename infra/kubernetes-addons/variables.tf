variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "new_relic_license_key" {
  description = "Chave de ingestao do New Relic armazenada no AWS Secrets Manager"
  type        = string
  sensitive   = true
  nullable    = false

  validation {
    condition     = length(trimspace(var.new_relic_license_key)) > 0
    error_message = "Informe uma chave de ingestao do New Relic nao vazia."
  }
}
