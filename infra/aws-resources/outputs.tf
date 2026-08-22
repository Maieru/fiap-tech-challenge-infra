output "eks" {
  value = var.create_eks_instance ? {
    name                = module.eks[0].cluster_name
    endpoint            = module.eks[0].cluster_endpoint
    ca                  = module.eks[0].cluster_certificate_authority_data
    security_group      = module.eks[0].cluster_security_group_id,
    node_security_group = module.eks[0].node_security_group_id
  } : null
}

output "backend_secret_arn" {
  description = "ARN do secret utilizado pelo backend"
  value       = try(aws_secretsmanager_secret.secret-manager-jwt-signing-key.arn, null)
}

output "vpc" {
  value = {
    id                         = module.vpc.vpc_id
    database_subnet_group_name = module.vpc.database_subnet_group_name
  }
}
