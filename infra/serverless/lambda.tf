locals {
  function_name       = "fiap-ordem-servico-authorizer"
  bootstrap_package   = "${path.module}/bootstrap.zip"
  database_secret_arn = data.terraform_remote_state.database.outputs.database_credentials_secret_arn
}

data "archive_file" "authorizer_bootstrap" {
  type        = "zip"
  output_path = local.bootstrap_package

  source {
    content  = "Pacote inicial. O codigo da Lambda e publicado pelo repositorio serverless."
    filename = "bootstrap.txt"
  }
}

resource "aws_iam_role" "authorizer" {
  name = "fiap-role-ordem-servico-authorizer"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Project = "fiap-tech-challenge"
  }
}

resource "aws_iam_role_policy_attachment" "authorizer_basic_execution" {
  role       = aws_iam_role.authorizer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "authorizer_vpc_access" {
  role       = aws_iam_role.authorizer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "authorizer_database_secret" {
  name = "fiap-policy-ordem-servico-authorizer-secret"
  role = aws_iam_role.authorizer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue"
        ]
        Resource = local.database_secret_arn
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "authorizer" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Project = "fiap-tech-challenge"
  }
}

resource "aws_lambda_function" "authorizer" {
  function_name = local.function_name
  description   = "Valida se o CPF possui acesso a ordem de servico"
  role          = aws_iam_role.authorizer.arn

  runtime = "dotnet10"
  handler = "Ftc.Authorizer::FIAP.TechChallenge.Serverless.OrdemServicoAuthorizer.Function::FunctionHandler"

  filename         = data.archive_file.authorizer_bootstrap.output_path
  source_code_hash = data.archive_file.authorizer_bootstrap.output_base64sha256

  architectures = ["x86_64"]
  memory_size   = var.lambda_memory_size
  timeout       = var.lambda_timeout_seconds

  environment {
    variables = {
      DATABASE_SECRET_ID = local.database_secret_arn
    }
  }

  logging_config {
    application_log_level = "INFO"
    log_format            = "JSON"
    log_group             = aws_cloudwatch_log_group.authorizer.name
    system_log_level      = "INFO"
  }

  vpc_config {
    subnet_ids         = local.private_subnet_ids
    security_group_ids = [aws_security_group.authorizer.id]
  }

  depends_on = [
    aws_iam_role_policy.authorizer_database_secret,
    aws_iam_role_policy_attachment.authorizer_basic_execution,
    aws_iam_role_policy_attachment.authorizer_vpc_access,
    aws_vpc_endpoint.secrets_manager
  ]

  lifecycle {
    ignore_changes = [
      filename,
      source_code_hash
    ]
  }

  tags = {
    Project = "fiap-tech-challenge"
  }
}
