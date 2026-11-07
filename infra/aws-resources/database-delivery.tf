resource "aws_eks_access_entry" "database_bootstrap" {
  count             = var.create_eks_instance ? 1 : 0
  cluster_name      = module.eks[0].cluster_name
  principal_arn     = data.terraform_remote_state.bootstrap.outputs.github_actions_infra_role_arn["database_infra"]
  kubernetes_groups = ["fiap:data-bootstrap"]
  type              = "STANDARD"
}
