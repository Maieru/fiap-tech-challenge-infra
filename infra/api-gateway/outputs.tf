output "api_endpoint" {
  description = "Endpoint publico que atende frontend e backend"
  value       = aws_apigatewayv2_api.main.api_endpoint
}

output "vpc_link_id" {
  description = "Identificador do VPC Link usado pela integracao privada"
  value       = aws_apigatewayv2_vpc_link.main.id
}

output "internal_alb_arn" {
  description = "ARN do ALB interno criado pelo AWS Load Balancer Controller"
  value       = data.aws_lb.internal_edge.arn
}
