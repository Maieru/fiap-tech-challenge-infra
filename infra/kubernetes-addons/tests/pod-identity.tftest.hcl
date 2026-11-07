mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "575638747623" }
  }
}
mock_provider "helm" {}
mock_provider "kubernetes" {}

override_data {
  target = data.terraform_remote_state.aws_resources
  values = { outputs = {
    eks = { name = "fiap-eks-cluster", endpoint = "https://eks.invalid", ca = "dGVzdA==" }
    vpc = { id = "vpc-test" }
  } }
}
variables { new_relic_license_key = "test-only" }

run "controller_can_chain_tagged_sessions_only_to_namespace_roles" {
  command = plan
  assert {
    condition = toset(jsondecode(aws_iam_role_policy.external_secrets.policy).Statement[0].Action) == toset([
      "sts:AssumeRole", "sts:TagSession"
    ])
    error_message = "O controller deve poder assumir roles e transmitir as tags do Pod Identity."
  }
  assert {
    condition = toset(jsondecode(aws_iam_role_policy.external_secrets.policy).Statement[0].Resource) == toset([
      for name in ["os", "execution", "billing", "observability", "data-bootstrap", "mongodb"] :
      "arn:aws:iam::575638747623:role/fiap-eso-${name}"
    ])
    error_message = "O encadeamento deve permanecer limitado as seis roles de namespaces."
  }
}
