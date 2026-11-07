output "api_endpoint" {
  description = "Endpoint publico que atende frontend e backend"
  value       = aws_apigatewayv2_api.main.api_endpoint
}

output "api_id" {
  description = "Identificador do HTTP API utilizado por integracoes externas"
  value       = aws_apigatewayv2_api.main.id
}

output "api_execution_arn" {
  description = "ARN de execucao do HTTP API"
  value       = aws_apigatewayv2_api.main.execution_arn
}

output "internal_alb_integration_id" {
  description = "Identificador da integracao HTTP proxy com o ALB interno"
  value       = aws_apigatewayv2_integration.internal_alb.id
}

output "vpc_link_id" {
  description = "Identificador do VPC Link usado pela integracao privada"
  value       = aws_apigatewayv2_vpc_link.main.id
}

output "internal_alb_arn" {
  description = "ARN do ALB interno criado pelo AWS Load Balancer Controller"
  value       = data.aws_lb.internal_edge.arn
}
