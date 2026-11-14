# Recursos Kubernetes compartilhados

O estágio kubernetes-configs cria namespaces, SecretStores, RBAC, CAs dos bancos e observabilidade. messaging mantém Kafka e MongoDB, armazenamento, NetworkPolicies e tópicos. Workloads de aplicação pertencem a OS, Execution e Billing.

| Namespace | Recursos/segredos |
| --- | --- |
| fiap-os | OS e credencial exclusiva PostgreSQL; JWT |
| fiap-execution | Execution e credencial exclusiva MongoDB; JWT |
| fiap-billing | Billing e credencial exclusiva PostgreSQL; JWT |
| fiap-frontend | Nginx/frontend e Ingresses |
| fiap-data-bootstrap | Jobs e credenciais administrativas dos bancos, ausentes nas APIs |
| fiap-observability | Collector/New Relic e licença |
| fiap-messaging | Kafka KRaft de um nó, PVC gp3 e tópicos |
| fiap-mongodb | MongoDB rs0 de um membro, autenticação/TLS e PVC gp3 criptografado de 20 GiB |

Cada SecretStore recebe uma role própria com acesso aos ARNs exatos necessários. O operador usa Pod Identity para assumir essas roles; aplicações não alteram SecretStores/RBAC nem leem Secrets diretamente. Roles publish/deploy são distintas por serviço, mas a confiança OIDC aceita o chamador principal em main.

O ConfigMap kafka-cluster guarda o cluster-id gerado por random_id.kafka no state de messaging. O StatefulSet Kafka referencia essa chave por env.valueFrom.configMapKeyRef; o manifesto YAML é estático para que apiVersion/kind/nome estejam disponíveis no primeiro plano Terraform. O broker é criado depois do ConfigMap e do armazenamento; não regenerar o ID mantendo um volume já formatado.

ConfigMaps aws-database-ca são criados em OS, Billing e bootstrap para RDS; os workloads montam /certs/global-bundle.pem como somente leitura. O arquivo público fica em certificates/global-bundle.pem. ConfigMaps mongodb-ca distribuem somente a CA pública gerada pelo DB para Execution (/certs/ca.pem) e bootstrap (/mongo-certs/ca.pem). O SecretStore de fiap-mongodb lê somente fiap-mongodb-admin; contém senha administrativa, keyfile e certificado/chave do servidor. Init container não root copia os arquivos para emptyDir em memória com modo 0400; a API nunca recebe esses arquivos privados.

O MongoDB usa a exceção localhost somente para iniciar rs0 e criar o primeiro administrador. Reinícios autenticam com o administrador existente e preservam os dados. A readiness exige primário de rs0; publishNotReadyAddresses no Service permite a resolução DNS durante a primeira eleição. NetworkPolicy restringe a porta 27017 à API Execution, aos Jobs administrativos e ao próprio MongoDB. Um membro/PVC não oferece alta disponibilidade; EBS permanece na mesma AZ.

Executar `node scripts/platform/test-mongodb.mjs` a partir do Infra com Docker e o repositório DB irmão disponível. O ensaio cria recursos exclusivos e valida TLS obrigatório/hostname, autenticação, grants isolados/idempotentes, commit/rollback e persistência após reinício. `EXECUTION_TEST_IMAGE` permite executar também o gate CLI real da imagem da API. O ensaio remove containers, volumes e rede temporários.

Não aplicar diretamente os templates de observabilidade: Terraform injeta checksum/endpoint. Não introduzir dupla gestão de recursos Terraform e aplicação.

A entrada operacional é manage-platform.yml do principal. Consultar o [guia central](https://github.com/Maieru/fiap-tech-challenge/blob/main/docs/operacao/plataforma-aws.md) para implantação, destruição diária e pré-requisitos de ativação.

## Verificação e gestão

Na raiz do Infra, o ensaio MongoDB exige Node.js 22+, Docker Linux e o checkout DB ao lado. Para incluir o gate da API, construa antes a imagem Execution e defina EXECUTION_TEST_IMAGE:

```powershell
$env:EXECUTION_TEST_IMAGE = 'fiap-execution:local'
node scripts/platform/test-mongodb.mjs
```

O gate é opcional quando a variável não está definida. O script cria recursos descartáveis próprios e não deve usar bancos ou volumes de desenvolvimento. Ele não substitui o gate executado no EKS.

Para inspecionar um cluster já configurado, confirme o contexto e consulte:

```powershell
kubectl -n fiap-mongodb get pods,services,pvc
kubectl -n fiap-messaging get pods,services,pvc,jobs
kubectl -n fiap-observability get pods,externalsecrets
```

Arquivos em k8s são consumidos pelo Terraform; não aplique a árvore inteira com kubectl. Placeholders/templates e recursos controlados pelo Terraform precisam ter uma única gestão. As aplicações são entregues por seus próprios catálogos e workflows reutilizáveis, após a inicialização dos bancos.
