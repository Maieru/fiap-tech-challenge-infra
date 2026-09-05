# FIAP Tech Challenge — Infrastructure

Infraestrutura compartilhada do projeto na AWS, provisionada com Terraform e Kubernetes. Inclui API Gateway, VPC Link e o AWS Load Balancer Controller usado para publicar frontend e backend por um ALB interno compartilhado.

Consulte o [guia de infraestrutura](infra/README.md) para conhecer os estados, dependências e comandos de execução.

O banco PostgreSQL é mantido separadamente no repositório [`fiap-tech-challenge-db`](https://github.com/Maieru/fiap-tech-challenge-db).

## New Relic

A observabilidade utiliza OpenTelemetry Collector e New Relic. Consulte [configuração, credenciais e migração](src/ObservabilityConfig/README.md).
