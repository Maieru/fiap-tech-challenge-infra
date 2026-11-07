output "github_actions_infra_role_arn" {
  value = { for key, role in aws_iam_role.github_actions_infra : key => role.arn }
}
