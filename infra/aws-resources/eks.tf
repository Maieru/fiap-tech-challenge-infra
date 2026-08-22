locals {
  github_infra_role_arn = data.terraform_remote_state.bootstrap.outputs.github_actions_infra_role_arn["k8s_infra"]
  github_app_role_arn   = data.terraform_remote_state.bootstrap.outputs.github_actions_role_arns["app"]
}

module "eks" {
  count = var.create_eks_instance ? 1 : 0

  source  = "terraform-aws-modules/eks/aws"
  version = "21.24.0"

  name               = "fiap-eks-cluster"
  kubernetes_version = "1.36"

  endpoint_public_access  = true
  endpoint_private_access = true

  enable_cluster_creator_admin_permissions = false

  kms_key_administrators = [
    "arn:aws:iam::575638747623:user/cli-user",
    local.github_infra_role_arn,
    local.github_app_role_arn
  ]

  access_entries = {
    github_actions_infra = {
      principal_arn = local.github_infra_role_arn

      policy_associations = {
        cluster_admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    },
    github_actions_app = {
      principal_arn = local.github_app_role_arn

      policy_associations = {
        namespace_admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"

          access_scope = {
            type       = "namespace"
            namespaces = ["fiap-backend", "fiap-frontend"]
          }
        }
      }
    },
    cli_user = {
      principal_arn = "arn:aws:iam::575638747623:user/cli-user"

      policy_associations = {
        cluster_admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
    }

    eks-pod-identity-agent = {
      before_compute = true
    }
  }

  eks_managed_node_groups = {
    fiap-node-group = {
      instance_types = ["t3.small"]

      min_size     = 1
      max_size     = 4
      desired_size = 3

      iam_role_additional_policies = {
        AmazonEKSWorkerNodePolicy          = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
        AmazonEKS_CNI_Policy               = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
      }
    }
  }
}
