output "lambda_function_arn" {
  description = "ARN da Lambda authorizer de ordem de servico"
  value       = aws_lambda_function.authorizer.arn
}

output "api_gateway_authorizer_id" {
  description = "Identificador do authorizer configurado no HTTP API"
  value       = aws_apigatewayv2_authorizer.ordem_servico.id
}

output "protected_route_keys" {
  description = "Rotas protegidas pelo authorizer de CPF"
  value       = sort(tolist(local.protected_routes))
}
