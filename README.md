# Infraestrutura AWS dos microsserviços

Terraform provisiona VPC, EKS/ECR, IAM, EBS CSI, External Secrets, Kafka, MongoDB, observabilidade e API Gateway. RDS e os segredos/certificados dos bancos pertencem ao repositório DB; aplicações mantêm imagens, migrations e workloads. O monólito e o authorizer Lambda não fazem parte do ciclo novo.

A entrada operacional é **Manage AWS microservices platform**, no repositório principal. Ela chama os workflows reutilizáveis deste repositório, com commits explícitos e OIDC do chamador central. Não há execução manual avulsa de provisionamento.

Consulte o [guia dos estágios e bootstrap](infra/README.md) e o [guia operacional central](https://github.com/Maieru/fiap-tech-challenge/blob/main/docs/operacao/plataforma-aws.md). Antes da primeira ativação, retirar o legado com as versões antigas indicadas no guia; não aplicar declarações novas em estados legados ocupados.

## Estágios ativos

| Estágio | Responsabilidade |
| --- | --- |
| bootstrap | Backend S3 protegido/versionado, OIDC e roles das pipelines; execução administrativa inicial |
| aws-resources | Rede, EKS/ECR, Pod Identity, EBS CSI, credencial JWT aleatória e access entries |
| kubernetes-addons | Controllers, metrics-server e licença New Relic |
| kubernetes-configs | Namespaces, RBAC, SecretStores/roles por namespace, CAs e observabilidade |
| messaging | Kafka KRaft e MongoDB replica set, PVCs gp3, Services internos, NetworkPolicies e tópicos |
| api-gateway | HTTPS público, VPC Link e integração com listener ALB recebido por input |

O diretório infra/serverless permanece como referência de retirada do legado, não é um estágio aceito pelo workflow novo. Não deve ser aplicado após a transição.

A criação intercala database (DB), inicialização, publicação/deploy das aplicações e Ingresses. Destroy remove tudo em ordem inversa e preserva somente bootstrap/state/roles das pipelines. Dados, EBS e imagens ECR são descartáveis; não há snapshots finais dos bancos.

No Manage AWS, o destroy remove aplicações → messaging (MongoDB/Kafka e discos) → database (RDS e inventário dos dados) → configurações → add-ons → core. Em messaging, o script ajusta reclaim dos PVs vinculados a PVCs dos namespaces `fiap-mongodb`/`fiap-messaging` para Delete, exclui PVCs restantes após o Terraform e aguarda a exclusão EBS. O estágio DB bloqueia a retirada dos controllers se ainda encontrar bancos ou discos do projeto. `terraform-destroy.test.mjs` exercita esse script com comandos simulados, incluindo falhas e rejeição de volume inválido, sem executar AWS.

## Verificação local

Executar terraform fmt -check e, para cada estágio ativo, terraform init -backend=false e terraform validate com TF_DATA_DIR isolado. Essas verificações não acessam o backend nem comprovam IAM, conectividade ou compatibilidade AWS. O fluxo remoto executa preflight regional, gates de persistência e smoke; consultar o guia central para o ensaio completo.

## Credenciais Mercado Pago

O estágio `aws-resources` cria `fiap-billing-mercadopago-credentials` e expõe `mercado_pago_secret_arn`. O workflow reutilizável recebe `MERCADO_PAGO_ACCESS_TOKEN` e `MERCADO_PAGO_WEBHOOK_SECRET` do orquestrador principal e grava os valores via `scripts/platform/sync-mercado-pago-secret.mjs` após apply. Os valores não são variáveis nem recursos `secret_version` Terraform. A role OIDC de infraestrutura gerencia o segredo, e somente o SecretStore Billing recebe acesso de leitura. O bootstrap IAM precisa ser atualizado antes do primeiro apply com essa integração. O destroy inclui a espera de exclusão do novo segredo e não exige essas credenciais.
