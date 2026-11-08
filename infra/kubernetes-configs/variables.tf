variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "destroy_mode" {
  description = "Exclusivo do plano -destroy: permite remover configs mesmo quando o state database ja foi esvaziado."
  type        = bool
  default     = false
}

variable "new_relic_otlp_endpoint" {
  description = "Endpoint regional HTTPS de ingestao OTLP do New Relic."
  type        = string
  default     = "https://otlp.nr-data.net"

  validation {
    condition = contains([
      "https://otlp.nr-data.net",
      "https://otlp.eu01.nr-data.net"
    ], var.new_relic_otlp_endpoint)
    error_message = "Use o endpoint HTTPS US ou EU do New Relic, sem barra final."
  }
}
