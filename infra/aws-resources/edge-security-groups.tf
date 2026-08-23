resource "aws_security_group" "api_gateway_vpc_link" {
  name        = "fiap-api-gateway-vpc-link-sg"
  description = "Saida do VPC Link do API Gateway para o ALB interno"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name    = "fiap-api-gateway-vpc-link-sg"
    Project = "fiap-tech-challenge"
  }
}

resource "aws_security_group" "internal_alb" {
  name        = "fiap-internal-alb-sg"
  description = "Entrada privada do ALB compartilhado pelo frontend e backend"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name    = "fiap-internal-alb-sg"
    Project = "fiap-tech-challenge"
  }
}

resource "aws_vpc_security_group_egress_rule" "vpc_link_to_internal_alb" {
  security_group_id            = aws_security_group.api_gateway_vpc_link.id
  referenced_security_group_id = aws_security_group.internal_alb.id
  description                  = "Permite que o VPC Link acesse o listener HTTP do ALB"
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "internal_alb_from_vpc_link" {
  security_group_id            = aws_security_group.internal_alb.id
  referenced_security_group_id = aws_security_group.api_gateway_vpc_link.id
  description                  = "Aceita trafego HTTP somente do VPC Link"
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "internal_alb_to_frontend" {
  security_group_id = aws_security_group.internal_alb.id
  description       = "Permite que o ALB acesse os pods do frontend"
  cidr_ipv4         = module.vpc.vpc_cidr_block
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "internal_alb_to_backend" {
  security_group_id = aws_security_group.internal_alb.id
  description       = "Permite que o ALB acesse os pods do backend"
  cidr_ipv4         = module.vpc.vpc_cidr_block
  from_port         = 8080
  to_port           = 8080
  ip_protocol       = "tcp"
}
