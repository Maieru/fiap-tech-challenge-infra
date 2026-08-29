locals {
  protected_routes = toset([
    "GET /api/ordensservico/acompanhamento/{id}",
    "PUT /api/ordensservico/{id}/aprovar-execucao",
    "PUT /api/ordensservico/{id}/cancelar"
  ])

  api_id             = data.terraform_remote_state.api_gateway.outputs.api_id
  api_execution_arn  = data.terraform_remote_state.api_gateway.outputs.api_execution_arn
  api_integration_id = data.terraform_remote_state.api_gateway.outputs.internal_alb_integration_id
}

resource "aws_apigatewayv2_authorizer" "ordem_servico" {
  api_id          = local.api_id
  name            = "ordem-servico-cpf-authorizer"
  authorizer_type = "REQUEST"
  authorizer_uri  = aws_lambda_function.authorizer.invoke_arn

  authorizer_payload_format_version = "2.0"
  authorizer_result_ttl_in_seconds  = 0
  enable_simple_responses           = true
  identity_sources                  = ["$request.header.X-CPF"]
}

resource "aws_lambda_permission" "api_gateway_authorizer" {
  statement_id  = "AllowApiGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${local.api_execution_arn}/authorizers/${aws_apigatewayv2_authorizer.ordem_servico.id}"
}

resource "aws_apigatewayv2_route" "ordem_servico_protected" {
  for_each = local.protected_routes

  api_id    = local.api_id
  route_key = each.value
  target    = "integrations/${local.api_integration_id}"

  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.ordem_servico.id
}
