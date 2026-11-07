# Recursos Kubernetes compartilhados

O estágio kubernetes-configs cria namespaces, SecretStores, RBAC, CAs AWS e observabilidade. messaging mantém Kafka, armazenamento, NetworkPolicy e tópicos. Workloads de aplicação pertencem a OS, Execution e Billing.

| Namespace | Recursos/segredos |
| --- | --- |
| fiap-os | OS e credencial exclusiva PostgreSQL; JWT |
| fiap-execution | Execution e credencial exclusiva DocumentDB; JWT |
| fiap-billing | Billing e credencial exclusiva PostgreSQL; JWT |
| fiap-frontend | Nginx/frontend e Ingresses |
| fiap-data-bootstrap | Jobs e credenciais administrativas dos bancos, ausentes nas APIs |
| fiap-observability | Collector/New Relic e licença |
| fiap-messaging | Kafka KRaft de um nó, PVC gp3 e tópicos |

Cada SecretStore recebe uma role própria com acesso aos ARNs exatos necessários. O operador usa Pod Identity para assumir essas roles; aplicações não alteram SecretStores/RBAC nem leem Secrets diretamente. Roles publish/deploy são distintas por serviço, mas a confiança OIDC aceita o chamador principal em main.

ConfigMaps aws-database-ca são criados nos namespaces das APIs e do bootstrap; os workloads montam /certs/global-bundle.pem como somente leitura. O arquivo público fica em certificates/global-bundle.pem; atualização/hash estão no guia central.

Não aplicar diretamente os templates de observabilidade: Terraform injeta checksum/endpoint. Não introduzir dupla gestão de recursos Terraform e aplicação. A árvore backend foi retirada.

A entrada operacional é manage-platform.yml do principal. Consultar o [guia central](https://github.com/Maieru/fiap-tech-challenge/blob/main/docs/operacao/plataforma-aws.md) para implantação, destruição diária e transição do legado.
