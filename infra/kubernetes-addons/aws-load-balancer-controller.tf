resource "aws_iam_role" "aws_load_balancer_controller" {
  name        = "fiap-role-aws-load-balancer-controller"
  description = "Permissoes do AWS Load Balancer Controller no EKS"

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

resource "aws_iam_policy" "aws_load_balancer_controller" {
  name        = "fiap-policy-aws-load-balancer-controller"
  description = "Policy oficial do AWS Load Balancer Controller"
  policy      = file("${path.module}/aws-load-balancer-controller-policy.json")
}

resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller" {
  role       = aws_iam_role.aws_load_balancer_controller.name
  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
}

resource "aws_eks_pod_identity_association" "aws_load_balancer_controller" {
  cluster_name    = data.terraform_remote_state.aws_resources.outputs.eks.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.aws_load_balancer_controller.arn

  depends_on = [aws_iam_role_policy_attachment.aws_load_balancer_controller]
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "3.5.0"
  namespace  = "kube-system"
  wait       = true
  timeout    = 600
  atomic     = true

  set {
    name  = "clusterName"
    value = data.terraform_remote_state.aws_resources.outputs.eks.name
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = data.terraform_remote_state.aws_resources.outputs.vpc.id
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  depends_on = [aws_eks_pod_identity_association.aws_load_balancer_controller]
}
