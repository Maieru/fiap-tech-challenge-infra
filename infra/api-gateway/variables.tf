variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "throttling_rate_limit" {
  description = "Quantidade sustentada de requisicoes por segundo no stage"
  type        = number
  default     = 100
}

variable "throttling_burst_limit" {
  description = "Quantidade maxima de requisicoes em rajada no stage"
  type        = number
  default     = 200
}
