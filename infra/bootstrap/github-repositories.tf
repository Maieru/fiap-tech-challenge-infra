locals {
  github_repositories = {
    app = {
      repositories = ["fiap-tech-challenge"]
      role_name    = "fiap-role-github-actions-app"
    }

    auth = {
      repositories = ["fiap-tech-challenge", "fiap-tech-challenge-serverless"]
      role_name    = "fiap-role-github-actions-auth"
    }

    k8s_infra = {
      repositories = ["fiap-tech-challenge", "fiap-tech-challenge-infra"]
      role_name    = "fiap-role-github-actions-infra"
    }

    database_infra = {
      repositories = ["fiap-tech-challenge", "fiap-tech-challenge-db"]
      role_name    = "fiap-role-github-actions-database"
    }
  }
}
