locals {
  github_repositories = {
    k8s_infra      = { repositories = ["fiap-tech-challenge"], role_name = "fiap-role-github-actions-infra" }
    database_infra = { repositories = ["fiap-tech-challenge"], role_name = "fiap-role-github-actions-database" }
  }
}
