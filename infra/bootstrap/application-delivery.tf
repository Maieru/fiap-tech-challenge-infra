locals {
  application_delivery = {
    os = {
      repository = "fiap-tech-challenge"
      ecr_names  = ["fiap-ecr-os-repository", "fiap-ecr-frontend-repository"]
    }
    execution = {
      repository = "fiap-tech-challenge-execution"
      ecr_names  = ["fiap-ecr-execution-repository"]
    }
    billing = {
      repository = "fiap-tech-challenge-billing"
      ecr_names  = ["fiap-ecr-billing-repository"]
    }
  }
  application_delivery_roles = merge([
    for service, config in local.application_delivery : {
      for operation in ["publish", "deploy"] : "${service}_${operation}" => {
        service    = service
        repository = config.repository
        operation  = operation
        ecr_names  = config.ecr_names
      }
    }
  ]...)
}

# Roles próprias: incluir serviços no mapa legado também criaria roles de Infra.
resource "aws_iam_role" "application_delivery" {
  for_each = local.application_delivery_roles
  name     = "fiap-github-${each.value.service}-${each.value.operation}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.oicd-github-actions.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_owner}/${each.value.repository}:ref:refs/heads/${var.github_branch}"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "application_delivery" {
  for_each = local.application_delivery_roles
  name     = "application-${each.value.operation}"
  role     = aws_iam_role.application_delivery[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
        Sid    = "ReadApplicationImages"
        Effect = "Allow"
        Action = ["ecr:DescribeImages", "ecr:DescribeRepositories"]
        Resource = [
          for name in each.value.ecr_names :
          "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${name}"
        ]
      }],
      each.value.operation == "publish" ? [
        {
          Sid      = "EcrLogin"
          Effect   = "Allow"
          Action   = ["ecr:GetAuthorizationToken"]
          Resource = ["*"]
        },
        {
          Sid    = "PublishApplicationImages"
          Effect = "Allow"
          Action = [
            "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload",
            "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage",
            "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"
          ]
          Resource = [
            for name in each.value.ecr_names :
            "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${name}"
          ]
        }
        ] : [{
          Sid      = "DescribeApplicationCluster"
          Effect   = "Allow"
          Action   = ["eks:DescribeCluster"]
          Resource = ["arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/fiap-eks-cluster"]
      }]
    )
  })
}

output "application_delivery_role_arns" {
  description = "Roles OIDC por servico e operacao, para vars AWS_PUBLISH_ROLE_ARN / AWS_DEPLOY_ROLE_ARN."
  value       = { for key, role in aws_iam_role.application_delivery : key => role.arn }
}
