data "aws_lb" "internal_edge" {
  name = "fiap-internal-edge"
}

data "aws_lb_listener" "http" {
  load_balancer_arn = data.aws_lb.internal_edge.arn
  port              = 80
}

resource "aws_apigatewayv2_vpc_link" "main" {
  name = "fiap-api-gateway-vpc-link"

  subnet_ids = data.terraform_remote_state.aws_resources.outputs.vpc.application_private_subnet_ids
  security_group_ids = [
    data.terraform_remote_state.aws_resources.outputs.vpc.api_gateway_vpc_link_security_group
  ]

  tags = {
    Project = "fiap-tech-challenge"
  }
}

resource "aws_apigatewayv2_api" "main" {
  name          = "fiap-tech-challenge"
  protocol_type = "HTTP"

  tags = {
    Project = "fiap-tech-challenge"
  }
}

resource "aws_apigatewayv2_integration" "internal_alb" {
  api_id = aws_apigatewayv2_api.main.id

  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = data.aws_lb_listener.http.arn
  connection_type        = "VPC_LINK"
  connection_id          = aws_apigatewayv2_vpc_link.main.id
  payload_format_version = "1.0"

  request_parameters = {
    "overwrite:path" = "$request.path"
  }
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.internal_alb.id}"
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/fiap-tech-challenge"
  retention_in_days = 7

  tags = {
    Project = "fiap-tech-challenge"
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit  = var.throttling_rate_limit
    throttling_burst_limit = var.throttling_burst_limit
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId          = "$context.requestId"
      requestTime        = "$context.requestTime"
      httpMethod         = "$context.httpMethod"
      routeKey           = "$context.routeKey"
      path               = "$context.path"
      status             = "$context.status"
      protocol           = "$context.protocol"
      responseLength     = "$context.responseLength"
      responseLatency    = "$context.responseLatency"
      integrationStatus  = "$context.integration.status"
      integrationLatency = "$context.integration.latency"
    })
  }

  depends_on = [aws_apigatewayv2_route.default]

  tags = {
    Project = "fiap-tech-challenge"
  }
}
