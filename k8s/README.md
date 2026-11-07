# Recursos Kubernetes compartilhados

Esta árvore pertence ao estágio Terraform `infra/kubernetes-configs`. O módulo descobre automaticamente `*/infra/namespace.yaml` e `*/infra/secret-store.yaml` (também aceita .yml). Os templates de `observability/application` são renderizados pelo Terraform; não os aplique diretamente com kubectl.

OS, Execution e Billing mantêm seus Deployments, Services, ConfigMaps, ExternalSecrets e HPAs nos repositórios de aplicação. Aqui são criados os namespaces `fiap-os`, `fiap-execution`, `fiap-billing` e um SecretStore `aws-secrets-store` em cada namespace. Os SecretStores seguem a região `us-east-1` do laboratório; ajuste os YAMLs se mover os segredos para outra região.

## Identidades e ECR para as Actions

O estágio `bootstrap` declara roles separadas `fiap-github-{os,execution,billing}-{publish,deploy}`, com OIDC restrito ao repositório e à branch main configurada. Publish escreve somente no ECR do serviço (OS também publica frontend); deploy consulta imagens e descreve o cluster, sem permissão para publicar imagens. As novas roles não recebem as policies amplas legadas de Infra.

`aws-resources` cria `fiap-ecr-os-repository`, `fiap-ecr-execution-repository` e `fiap-ecr-billing-repository` com tags imutáveis, além de access entries STANDARD para as roles deploy, com grupos `fiap:deploy-{serviço}`. O ECR frontend existente é reutilizado.

`kubernetes-configs/application-delivery.tf` cria Roles/RoleBindings: OS acessa fiap-os e fiap-frontend; Execution/Billing acessam somente seu namespace. Incluem leitura/escrita dos recursos de aplicação e leitura de status do SecretStore; não incluem Secrets, namespaces, CRDs ou RBAC. Recursos antigos e acessos legados não são retirados por esta adição.

Aplicar bootstrap → aws-resources → kubernetes-configs antes de usar as Actions. O bootstrap exporta `application_delivery_role_arns`; cada repositório configura seus outputs `{serviço}_publish`/`{serviço}_deploy` nas Actions variables `AWS_PUBLISH_ROLE_ARN`/`AWS_DEPLOY_ROLE_ARN`. Os workflows operam no cluster fiap-eks-cluster. Provisionamento dos bancos/Kafka/segredos e concessão IAM do operador continuam pré-requisitos independentes.

## Dependências de segredos e IAM

| Segredo AWS | Propriedade JSON | Destino Kubernetes |
| --- | --- | --- |
| fiap-os-database-credentials | ConnectionStrings__DefaultConnection | fiap-os / fiap-os-database-credentials |
| fiap-execution-database-credentials | Mongo__ConnectionString | fiap-execution / fiap-execution-database-credentials |
| fiap-billing-database-credentials | ConnectionStrings__DefaultConnection | fiap-billing / fiap-billing-database-credentials |
| fiap-secret-manager-jwt-signing-key | Jwt__SigningKey | Secret JWT separado em cada namespace de API |
| fiap-newrelic-license | license-key | fiap-observability / newrelic-license |

Os três primeiros segredos precisam ser criados separadamente, com usuários/senhas distintos e grants limitados ao banco correspondente. Os YAMLs de aplicação importam somente a propriedade listada. Não utilizam o segredo do RDS legado nem concedem permissões no banco.

Antes do rollout, conceda à role `fiap-role-external-secrets` acesso de DescribeSecret/GetSecretValue aos ARNs exatos dos três novos segredos. A política em `infra/kubernetes-addons/external-secrets.tf` ainda contém somente os ARNs antigos e o New Relic; esta entrega não cria nem amplia IAM. Preserve acesso ao JWT e à licença. Se usar CMK própria, providencie a permissão de descriptografia correspondente.

A autenticação dos SecretStores usa a identidade do operador External Secrets já associada pelo EKS Pod Identity. As APIs não precisam de identidade AWS nem de token Kubernetes. O operador central possui acesso aos segredos autorizados; a separação aplicada aqui é das credenciais e referências entregues a cada aplicação, não uma role AWS por namespace.

## Observabilidade e autoscaling

Reutilizar Collector, ConfigMap com os pipelines de traces/métricas/logs, Service 4317/4318, SecretStore e ExternalSecret existentes em `fiap-observability`. A licença é consumida pelo Collector e pela integração Kubernetes existente, nunca pelas APIs ou pelo navegador.

As APIs usam OTLP gRPC em HTTP 4317; o Nginx encaminha OTLP/HTTP a 4318. O Collector usa HTTPS para New Relic. `new_relic_otlp_endpoint` no estágio `kubernetes-configs` seleciona US (padrão) ou EU. Não é necessário um Collector por serviço ou um agente adicional de APM nas APIs já instrumentadas.

O metrics-server de `kubernetes-addons` atende aos HPAs (1 a 3 réplicas, CPU 70%); a integração New Relic Kubernetes coleta recursos/estado do cluster separadamente. Considere memória/CPU dos agentes, aplicações e pods adicionais de RollingUpdate na capacidade dos nodes.

## Sequência e validação

Preparar infraestrutura/add-ons → namespaces/SecretStores/observabilidade → novos segredos/IAM e bancos/Kafka/tópicos → migrations PostgreSQL → ExternalSecrets das APIs prontos → aplicações/HPAs → frontend.

Validar `terraform fmt -check`, `terraform validate` com providers inicializados, schemas YAML e sincronização dos ExternalSecrets antes do rollout. No cluster, conferir Collector pronto, `kubectl top pods`, HPA com métricas disponíveis e chegada dos três sinais por serviço no New Relic.

A aplicação desta árvore continua sob o fluxo Infra existente. Não executar Terraform apply ou remover recursos legados como parte da preparação dos manifestos. A criação dos novos segredos/permissões do operador, bancos, Kafka e migração de dados permanece fora desta entrega. A publicação de imagens é preparada pelas novas Actions dos repositórios de aplicação, sem execução remota nesta implementação.
