mock_provider "aws" {}
mock_provider "helm" {}
mock_provider "kubernetes" {}

override_data {
  target = data.terraform_remote_state.aws_resources
  values = { outputs = {
    eks                     = { name = "fiap-eks-cluster", endpoint = "https://eks.invalid", ca = "dGVzdA==" }
    backend_secret_arn      = "arn:aws:secretsmanager:us-east-1:575638747623:secret:fiap-secret-manager-jwt-signing-key-test01"
    mercado_pago_secret_arn = "arn:aws:secretsmanager:us-east-1:575638747623:secret:fiap-billing-mercadopago-credentials-test01"
  } }
}
override_data {
  target = data.terraform_remote_state.kubernetes_addons
  values = { outputs = {
    external_secrets_role_arn = "arn:aws:iam::575638747623:role/fiap-role-external-secrets"
    newrelic_secret_arn       = "arn:aws:secretsmanager:us-east-1:575638747623:secret:fiap-newrelic-license-test01"
  } }
}
override_data {
  target = data.terraform_remote_state.database[0]
  values = { outputs = {
    mongodb_ca_pem = "test-public-ca"
    database_secret_arns = {
      os             = "arn:aws:secretsmanager:us-east-1:575638747623:secret:fiap-os-database-credentials-test01"
      execution      = "arn:aws:secretsmanager:us-east-1:575638747623:secret:fiap-execution-database-credentials-test01"
      billing        = "arn:aws:secretsmanager:us-east-1:575638747623:secret:fiap-billing-database-credentials-test01"
      postgres_admin = "arn:aws:secretsmanager:us-east-1:575638747623:secret:fiap-postgres-admin-test01"
      mongodb_admin  = "arn:aws:secretsmanager:us-east-1:575638747623:secret:fiap-mongodb-admin-test01"
    }
  } }
}

run "namespace_trust_accepts_tags_without_expanding_principal_or_secret_access" {
  command = plan
  variables {
    destroy_mode = false
  }
  assert {
    condition     = length(data.terraform_remote_state.database) == 1 && length(local.database_secret_arns) == 5 && local.mongodb_ca_pem == "test-public-ca"
    error_message = "O apply deve continuar lendo os ARNs e a CA do state database."
  }
  assert {
    condition = alltrue([for role in aws_iam_role.secret_store :
      toset(jsondecode(role.assume_role_policy).Statement[0].Action) == toset(["sts:AssumeRole", "sts:TagSession"]) &&
      jsondecode(role.assume_role_policy).Statement[0].Principal.AWS == "arn:aws:iam::575638747623:role/fiap-role-external-secrets"
    ])
    error_message = "Cada role deve aceitar as tags somente do controller External Secrets."
  }
  assert {
    condition = alltrue([for name, policy in aws_iam_role_policy.secret_store :
      toset(jsondecode(policy.policy).Statement[0].Action) == toset(["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"]) &&
      toset(jsondecode(policy.policy).Statement[0].Resource) == toset(local.secret_access[name]) &&
      !contains(jsondecode(policy.policy).Statement[0].Resource, "*")
    ])
    error_message = "A permissao de tags nao deve ampliar a leitura dos segredos."
  }
  assert {
    condition = alltrue([for name, resources in local.secret_access :
      contains(resources, data.terraform_remote_state.aws_resources.outputs.mercado_pago_secret_arn) == (name == "billing")
    ])
    error_message = "Somente o namespace Billing pode ler a credencial Mercado Pago."
  }
  assert {
    condition = alltrue([for secret in kubernetes_manifest.bootstrap_secrets :
      can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", secret.manifest.metadata.name)) &&
      secret.manifest.metadata.name == secret.manifest.spec.target.name
    ])
    error_message = "ExternalSecret e Secret de bootstrap devem usar o mesmo nome DNS valido."
  }
}

run "destroy_recovers_without_reading_database_state_or_outputs" {
  command = plan
  variables {
    destroy_mode = true
  }
  assert {
    condition     = length(data.terraform_remote_state.database) == 0 && length(local.database_secret_arns) == 0 && local.mongodb_ca_pem == ""
    error_message = "A recuperacao do destroy nao pode consultar o state database ja vazio."
  }
  assert {
    condition     = length(kubernetes_manifest.bootstrap_secrets) == 0 && length(local.secret_access.mongodb) == 0 && length(local.secret_access["data-bootstrap"]) == 0
    error_message = "O destroy nao deve inventar ARNs ou recriar secrets dos bancos excluidos."
  }
}
