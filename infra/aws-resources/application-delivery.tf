resource "aws_ecr_repository" "application" {
  for_each             = toset(["os", "execution", "billing"])
  name                 = "fiap-ecr-${each.key}-repository"
  image_tag_mutability = "IMMUTABLE"
}

# RBAC e aplicado pelo kubernetes-configs; nenhuma role de aplicacao e cluster-admin.
resource "aws_eks_access_entry" "application_delivery" {
  for_each = var.create_eks_instance ? toset(["os", "execution", "billing"]) : toset([])

  cluster_name      = module.eks[0].cluster_name
  principal_arn     = data.terraform_remote_state.bootstrap.outputs.application_delivery_role_arns["${each.key}_deploy"]
  kubernetes_groups = ["fiap:deploy-${each.key}"]
  type              = "STANDARD"
}

output "application_ecr_repository_urls" {
  value = { for service, repository in aws_ecr_repository.application : service => repository.repository_url }
}
