# O valor e cadastrado no Secrets Manager, fora do estado Terraform.
resource "aws_secretsmanager_secret" "newrelic_license" {
  name                    = "fiap-newrelic-license"
  description             = "New Relic ingest license key for OpenTelemetry Collector"
  recovery_window_in_days = 7
}
