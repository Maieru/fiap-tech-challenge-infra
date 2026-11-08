resource "aws_secretsmanager_secret" "mercado_pago" {
  name                    = "fiap-billing-mercadopago-credentials"
  recovery_window_in_days = 0
}

output "mercado_pago_secret_arn" {
  description = "Segredo do checkout Mercado Pago utilizado somente pelo Billing."
  value       = aws_secretsmanager_secret.mercado_pago.arn
}
