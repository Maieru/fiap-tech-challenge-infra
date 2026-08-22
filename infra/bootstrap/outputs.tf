output "github_actions_infra_role_arn" {
  description = "ARN da IAM Role usada pelo GitHub Actions para Terraform infra"

  value = {
    for key, role in aws_iam_role.github_actions_infra :
    key => role.arn
  }
}

output "github_actions_role_arns" {
  description = "ARNs das roles utilizadas pelos GitHub Actions"

  value = {
    for key, role in aws_iam_role.github_actions :
    key => role.arn
  }
}
