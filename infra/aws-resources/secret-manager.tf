resource "aws_secretsmanager_secret" "secret-manager-jwt-signing-key" {
  name                    = "fiap-secret-manager-jwt-signing-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "backend" {
  secret_id = aws_secretsmanager_secret.secret-manager-jwt-signing-key.id

  secret_string = jsonencode({
    "Jwt__SigningKey" = var.jwt_signing_key
  })
}
