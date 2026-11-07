data "terraform_remote_state" "database" {
  backend = "s3"
  config  = { bucket = "fiap-s3-terraform-backend", key = "terraform/database/terraform.tfstate", region = var.aws_region }
}
data "terraform_remote_state" "kubernetes_addons" {
  backend = "s3"
  config  = { bucket = "fiap-s3-terraform-backend", key = "terraform/kubernetes-addons/terraform.tfstate", region = var.aws_region }
}

locals {
  secret_access = {
    os             = [data.terraform_remote_state.database.outputs.database_secret_arns.os, data.terraform_remote_state.aws_resources.outputs.backend_secret_arn]
    execution      = [data.terraform_remote_state.database.outputs.database_secret_arns.execution, data.terraform_remote_state.aws_resources.outputs.backend_secret_arn]
    billing        = [data.terraform_remote_state.database.outputs.database_secret_arns.billing, data.terraform_remote_state.aws_resources.outputs.backend_secret_arn]
    observability  = [data.terraform_remote_state.kubernetes_addons.outputs.newrelic_secret_arn]
    data-bootstrap = values(data.terraform_remote_state.database.outputs.database_secret_arns)
    mongodb        = [data.terraform_remote_state.database.outputs.database_secret_arns.mongodb_admin]
  }
}
resource "aws_iam_role" "secret_store" {
  for_each = local.secret_access
  name     = "fiap-eso-${each.key}"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Principal = { AWS = data.terraform_remote_state.kubernetes_addons.outputs.external_secrets_role_arn }
    Action = "sts:AssumeRole"
  }] })
}
resource "aws_iam_role_policy" "secret_store" {
  for_each = local.secret_access
  name     = "read-namespace-secrets"
  role     = aws_iam_role.secret_store[each.key].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = ["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"], Resource = each.value
  }] })
}
resource "kubernetes_config_map_v1" "database_ca" {
  for_each = toset(["fiap-os", "fiap-billing", "fiap-data-bootstrap"])
  metadata {
    name      = "aws-database-ca"
    namespace = each.value
  }
  data       = { "global-bundle.pem" = file("${path.module}/../../k8s/certificates/global-bundle.pem") }
  depends_on = [kubernetes_namespace_v1.from_yaml]
}
resource "kubernetes_config_map_v1" "mongodb_ca" {
  for_each = toset(["fiap-execution", "fiap-data-bootstrap"])
  metadata {
    name      = "mongodb-ca"
    namespace = each.value
  }
  data       = { "ca.pem" = data.terraform_remote_state.database.outputs.mongodb_ca_pem }
  depends_on = [kubernetes_namespace_v1.from_yaml]
}
resource "kubernetes_manifest" "bootstrap_secrets" {
  for_each = data.terraform_remote_state.database.outputs.database_secret_arns
  manifest = {
    apiVersion = "external-secrets.io/v1", kind = "ExternalSecret"
    metadata   = { name = "database-${replace(each.key, "_", "-")}", namespace = "fiap-data-bootstrap" }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { name = "aws-secrets-store", kind = "SecretStore" }
      target          = { name = "database-${replace(each.key, "_", "-")}", creationPolicy = "Owner" }
      dataFrom        = [{ extract = { key = each.value } }]
    }
  }
  depends_on = [kubernetes_manifest.secret_store_from_yaml]
}
