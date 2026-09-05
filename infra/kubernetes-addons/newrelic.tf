resource "aws_secretsmanager_secret" "newrelic_license" {
  name                    = "fiap-newrelic-license"
  description             = "New Relic ingest license key for OpenTelemetry Collector"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "newrelic_license" {
  secret_id = aws_secretsmanager_secret.newrelic_license.id

  secret_string = jsonencode({
    "license-key" = var.new_relic_license_key
  })
}
