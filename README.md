# Infraestrutura AWS dos microsserviços

Terraform provisiona VPC, EKS/ECR, IAM, EBS CSI, External Secrets, Kafka, observabilidade e API Gateway. RDS/DocumentDB e seus segredos pertencem ao repositório DB; aplicações mantêm imagens, migrations e workloads. O monólito e o authorizer Lambda não fazem parte do ciclo novo.

A entrada operacional é **Manage AWS microservices platform**, no repositório principal. Ela chama os workflows reutilizáveis deste repositório, com commits explícitos e OIDC do chamador central. Não há execução manual avulsa de provisionamento.

Consulte o [guia dos estágios e bootstrap](infra/README.md) e o [guia operacional central](https://github.com/Maieru/fiap-tech-challenge/blob/main/docs/operacao/plataforma-aws.md). Antes da primeira ativação, retirar o legado com as versões antigas indicadas no guia; não aplicar declarações novas em estados legados ocupados.

## Estágios ativos

| Estágio | Responsabilidade |
| --- | --- |
| bootstrap | Backend S3 protegido/versionado, OIDC e roles das pipelines; execução administrativa inicial |
| aws-resources | Rede, EKS/ECR, Pod Identity, EBS CSI, credencial JWT aleatória e access entries |
| kubernetes-addons | Controllers, metrics-server e licença New Relic |
| kubernetes-configs | Namespaces, RBAC, SecretStores/roles por namespace, CAs e observabilidade |
| messaging | Kafka KRaft, PVC gp3, Service interno, NetworkPolicy e tópicos |
| api-gateway | HTTPS público, VPC Link e integração com listener ALB recebido por input |

O diretório infra/serverless permanece como referência de retirada do legado, não é um estágio aceito pelo workflow novo. Não deve ser aplicado após a transição.

A criação intercala database (DB), inicialização, publicação/deploy das aplicações e Ingresses. Destroy remove tudo em ordem inversa e preserva somente bootstrap/state/roles das pipelines. Dados, EBS e imagens ECR são descartáveis; não há snapshots finais dos bancos.

## Verificação local

Executar terraform fmt -check e, para cada estágio ativo, terraform init -backend=false e terraform validate com TF_DATA_DIR isolado. Essas verificações não acessam o backend nem comprovam IAM, conectividade ou compatibilidade AWS. O fluxo remoto executa preflight regional, gates de persistência e smoke; consultar o guia central para o ensaio completo.
