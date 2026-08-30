variable "aws_region" {
  description = "Regiao AWS dos recursos serverless"
  type        = string
  default     = "us-east-1"
}

variable "lambda_memory_size" {
  description = "Memoria em MB reservada para o authorizer"
  type        = number
  default     = 256
}

variable "lambda_timeout_seconds" {
  description = "Tempo limite de execucao do authorizer"
  type        = number
  default     = 30
}

variable "log_retention_days" {
  description = "Retencao dos logs da Lambda no CloudWatch"
  type        = number
  default     = 7
}
