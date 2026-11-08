resource "aws_iam_role" "github_actions_infra" {
  for_each = local.github_repositories
  name     = "${each.value.role_name}-infra"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.oicd-github-actions.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = { StringEquals = {
        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        "token.actions.githubusercontent.com:sub" = "repo:${var.github_owner}/fiap-tech-challenge:ref:refs/heads/${var.github_branch}"
      } }
    }]
  })
}
resource "aws_iam_policy" "platform_infra" {
  name = "fiap-policy-platform-infra"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:ListBucket"
        ],
        "Resource" : [
          "arn:aws:s3:::fiap-s3-terraform-backend"
        ],
        "Condition" : {
          "StringLike" : {
            "s3:prefix" : [
              "env:/*",
              "terraform/aws-resources/*",
              "terraform/kubernetes-addons/*",
              "terraform/kubernetes-configs/*",
              "terraform/messaging/*",
              "terraform/api-gateway/*",
              "terraform/bootstrap/*",
              "terraform/database/*"
            ]
          }
        }
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:GetObject"
        ],
        "Resource" : [
          "arn:aws:s3:::fiap-s3-terraform-backend/terraform/aws-resources/*",
          "arn:aws:s3:::fiap-s3-terraform-backend/terraform/kubernetes-addons/*",
          "arn:aws:s3:::fiap-s3-terraform-backend/terraform/kubernetes-configs/*",
          "arn:aws:s3:::fiap-s3-terraform-backend/terraform/messaging/*",
          "arn:aws:s3:::fiap-s3-terraform-backend/terraform/api-gateway/*",
          "arn:aws:s3:::fiap-s3-terraform-backend/terraform/bootstrap/*",
          "arn:aws:s3:::fiap-s3-terraform-backend/terraform/database/*"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:PutObject",
          "s3:DeleteObject"
        ],
        "Resource" : [
          "arn:aws:s3:::fiap-s3-terraform-backend/terraform/aws-resources/*",
          "arn:aws:s3:::fiap-s3-terraform-backend/terraform/kubernetes-addons/*",
          "arn:aws:s3:::fiap-s3-terraform-backend/terraform/kubernetes-configs/*",
          "arn:aws:s3:::fiap-s3-terraform-backend/terraform/messaging/*",
          "arn:aws:s3:::fiap-s3-terraform-backend/terraform/api-gateway/*"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2:*",
          "elasticloadbalancing:*",
          "eks:*",
          "apigateway:*",
          "logs:*",
          "cloudwatch:*",
          "kms:*"
        ],
        "Resource" : [
          "*"
        ]
      },
      {
        "Sid" : "ManageVpcDatabaseSubnetGroup",
        "Effect" : "Allow",
        "Action" : [
          "rds:DescribeDBSubnetGroups",
          "rds:CreateDBSubnetGroup",
          "rds:ModifyDBSubnetGroup",
          "rds:DeleteDBSubnetGroup",
          "rds:ListTagsForResource",
          "rds:AddTagsToResource",
          "rds:RemoveTagsFromResource"
        ],
        "Resource" : [
          "arn:aws:rds:${var.aws_region}:${data.aws_caller_identity.current.account_id}:subgrp:fiap-rds-subnet-group"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ecr:*"
        ],
        "Resource" : [
          "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/fiap-ecr-*"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "secretsmanager:*"
        ],
        "Resource" : [
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:fiap-secret-manager-jwt-signing-key-*",
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:fiap-newrelic-license-*",
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:fiap-billing-mercadopago-credentials-*"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "iam:GetRole",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:UpdateRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:TagPolicy",
          "iam:UntagPolicy",
          "iam:ListInstanceProfilesForRole",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile",
          "iam:UntagInstanceProfile"
        ],
        "Resource" : [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/fiap-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/fiap-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/fiap-*"
        ]
      },
      {
        "Sid" : "ReadEksNodegroupServiceLinkedRole",
        "Effect" : "Allow",
        "Action" : [
          "iam:GetRole"
        ],
        "Resource" : [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/eks-nodegroup.amazonaws.com/AWSServiceRoleForAmazonEKSNodegroup"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "iam:PassRole"
        ],
        "Resource" : [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/fiap-*"
        ],
        "Condition" : {
          "StringEquals" : {
            "iam:PassedToService" : [
              "eks.amazonaws.com",
              "ec2.amazonaws.com",
              "pods.eks.amazonaws.com"
            ]
          }
        }
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "iam:CreateServiceLinkedRole"
        ],
        "Resource" : [
          "*"
        ],
        "Condition" : {
          "StringEquals" : {
            "iam:AWSServiceName" : [
              "eks.amazonaws.com",
              "eks-nodegroup.amazonaws.com",
              "elasticloadbalancing.amazonaws.com"
            ]
          }
        }
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "iam:GetOpenIDConnectProvider"
        ],
        "Resource" : [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/oidc.eks.${var.aws_region}.amazonaws.com/*"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ],
        "Resource" : [
          "arn:aws:ssm:${var.aws_region}::parameter/aws/service/eks/*"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "sts:GetCallerIdentity"
        ],
        "Resource" : [
          "*"
        ]
      }
    ]
  })
}
resource "aws_iam_policy" "database_infra" {
  name = "fiap-policy-database-infra"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:ListBucket"
        ],
        "Resource" : [
          "arn:aws:s3:::fiap-s3-terraform-backend"
        ],
        "Condition" : {
          "StringLike" : {
            "s3:prefix" : [
              "env:/*",
              "terraform/database/*",
              "terraform/aws-resources/*"
            ]
          }
        }
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:GetObject"
        ],
        "Resource" : [
          "arn:aws:s3:::fiap-s3-terraform-backend/terraform/database/*",
          "arn:aws:s3:::fiap-s3-terraform-backend/terraform/aws-resources/*"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:PutObject",
          "s3:DeleteObject"
        ],
        "Resource" : [
          "arn:aws:s3:::fiap-s3-terraform-backend/terraform/database/*"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "rds:Describe*",
          "rds:ListTagsForResource"
        ],
        "Resource" : [
          "*"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "rds:CreateDBInstance",
          "rds:ModifyDBInstance",
          "rds:DeleteDBInstance",
          "rds:CreateDBCluster",
          "rds:ModifyDBCluster",
          "rds:DeleteDBCluster",
          "rds:CreateDBSubnetGroup",
          "rds:ModifyDBSubnetGroup",
          "rds:DeleteDBSubnetGroup",
          "rds:AddTagsToResource",
          "rds:RemoveTagsFromResource"
        ],
        "Resource" : [
          "arn:aws:rds:${var.aws_region}:${data.aws_caller_identity.current.account_id}:db:fiap-*",
          "arn:aws:rds:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster:fiap-*",
          "arn:aws:rds:${var.aws_region}:${data.aws_caller_identity.current.account_id}:subgrp:fiap-*",
          "arn:aws:rds:${var.aws_region}:${data.aws_caller_identity.current.account_id}:pg:*",
          "arn:aws:rds:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster-pg:*",
          "arn:aws:rds:${var.aws_region}:${data.aws_caller_identity.current.account_id}:og:*"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2:Describe*",
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:ModifySecurityGroupRules",
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ],
        "Resource" : [
          "*"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "secretsmanager:*"
        ],
        "Resource" : [
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:fiap-*-database-credentials-*",
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:fiap-postgres-admin-*",
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:fiap-documentdb-admin-*",
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:fiap-mongodb-admin-*"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "iam:CreateServiceLinkedRole"
        ],
        "Resource" : [
          "*"
        ],
        "Condition" : {
          "StringEquals" : {
            "iam:AWSServiceName" : [
              "rds.amazonaws.com"
            ]
          }
        }
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "eks:DescribeCluster"
        ],
        "Resource" : [
          "arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/fiap-eks-cluster"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "sts:GetCallerIdentity"
        ],
        "Resource" : [
          "*"
        ]
      }
    ]
  })
}
resource "aws_iam_role_policy" "inventory" {
  name = "platform-inventory"
  role = aws_iam_role.github_actions_infra["k8s_infra"].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = ["ecr:DescribeRepositories"], Resource = "*"
  }] })
}
resource "aws_iam_role_policy_attachment" "github_actions_infra_attach" {
  for_each   = aws_iam_role.github_actions_infra
  role       = each.value.name
  policy_arn = each.key == "k8s_infra" ? aws_iam_policy.platform_infra.arn : aws_iam_policy.database_infra.arn
}
