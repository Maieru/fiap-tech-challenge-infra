resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  wait             = true
  timeout          = 600
  atomic           = true

  depends_on = [
    helm_release.aws_load_balancer_controller,
    aws_eks_pod_identity_association.external_secrets
  ]
}

resource "aws_iam_role" "external_secrets" {
  name = "fiap-role-external-secrets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })
}

data "aws_caller_identity" "current" {}
resource "aws_iam_role_policy" "external_secrets" {
  name = "fiap-policy-external-secrets"
  role = aws_iam_role.external_secrets.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = ["sts:AssumeRole"]
    Resource = [for name in ["os", "execution", "billing", "observability", "data-bootstrap", "mongodb"] :
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/fiap-eso-${name}"]
  }] })
}
output "external_secrets_role_arn" { value = aws_iam_role.external_secrets.arn }
output "newrelic_secret_arn" { value = aws_secretsmanager_secret.newrelic_license.arn }

resource "aws_eks_pod_identity_association" "external_secrets" {
  cluster_name    = data.terraform_remote_state.aws_resources.outputs.eks.name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.external_secrets.arn

  depends_on = [aws_iam_role_policy.external_secrets]
}
