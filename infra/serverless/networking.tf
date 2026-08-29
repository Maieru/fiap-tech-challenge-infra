locals {
  vpc_id             = data.terraform_remote_state.aws_resources.outputs.vpc.id
  private_subnet_ids = data.terraform_remote_state.aws_resources.outputs.vpc.application_private_subnet_ids
  database_sg_id     = data.terraform_remote_state.database.outputs.database_security_group_id
}

resource "aws_security_group" "authorizer" {
  name        = "fiap-ordem-servico-authorizer-sg"
  description = "Saida da Lambda authorizer para PostgreSQL e Secrets Manager"
  vpc_id      = local.vpc_id

  tags = {
    Name    = "fiap-ordem-servico-authorizer-sg"
    Project = "fiap-tech-challenge"
  }
}

resource "aws_security_group" "secrets_manager_endpoint" {
  name        = "fiap-secrets-manager-endpoint-sg"
  description = "Entrada privada no endpoint do Secrets Manager"
  vpc_id      = local.vpc_id

  tags = {
    Name    = "fiap-secrets-manager-endpoint-sg"
    Project = "fiap-tech-challenge"
  }
}

resource "aws_vpc_security_group_egress_rule" "authorizer_to_database" {
  security_group_id            = aws_security_group.authorizer.id
  referenced_security_group_id = local.database_sg_id
  description                  = "Permite que o authorizer consulte o PostgreSQL"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "database_from_authorizer" {
  security_group_id            = local.database_sg_id
  referenced_security_group_id = aws_security_group.authorizer.id
  description                  = "Aceita consultas PostgreSQL da Lambda authorizer"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "authorizer_to_secrets_manager" {
  security_group_id            = aws_security_group.authorizer.id
  referenced_security_group_id = aws_security_group.secrets_manager_endpoint.id
  description                  = "Permite que o authorizer leia o segredo do banco"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "secrets_manager_from_authorizer" {
  security_group_id            = aws_security_group.secrets_manager_endpoint.id
  referenced_security_group_id = aws_security_group.authorizer.id
  description                  = "Aceita HTTPS da Lambda authorizer"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_endpoint" "secrets_manager" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = local.private_subnet_ids
  security_group_ids = [aws_security_group.secrets_manager_endpoint.id]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue"
        ]
        Resource = data.terraform_remote_state.database.outputs.database_credentials_secret_arn
      }
    ]
  })

  tags = {
    Name    = "fiap-secrets-manager-endpoint"
    Project = "fiap-tech-challenge"
  }
}
