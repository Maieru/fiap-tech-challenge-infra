# Estágios Terraform e bootstrap

Operação diária: workflow manage-platform.yml do repositório principal. Os workflows terraform-stage.yml, cleanup-applications.yml e verify-destroy.yml são reutilizáveis, sem workflow_dispatch, e só aceitam o chamador principal em main.

A [documentação central](https://github.com/Maieru/fiap-tech-challenge/blob/main/docs/operacao/plataforma-aws.md) contém variáveis, secrets, responsabilidades, sequência, transição do legado e retomada. Região us-east-1; Terraform 1.13.0 na pipeline.

## Bootstrap administrativo

Em uma conta existente, inicializar infra/bootstrap, revisar seu plano e aplicar com credenciais administrativas. O bootstrap atual remove identidades legadas app/auth; executar somente após a retirada remota de seus dependentes conforme o guia central. Outputs github_actions_infra_role_arn e application_delivery_role_arns configuram as Variables do principal.

Em uma conta nova, o backend não existe. Em um checkout exclusivo para bootstrap:

1. Renomear temporariamente infra/bootstrap/backend.tf para backend.tf.disabled.
2. Executar terraform -chdir=infra/bootstrap init, plan -out=<plano> e apply <plano>.
3. Restaurar backend.tf e executar terraform -chdir=infra/bootstrap init -migrate-state.
4. Guardar/remover cópias locais do state com o cuidado devido a dados sensíveis.

O bucket tem prevent_destroy, force_destroy=false, criptografia, bloqueio público e versionamento. O ciclo operacional não possui escrita no prefixo bootstrap nem permissão de destruição do bucket.

### Retomada após AccessDenied no DB Subnet Group

O módulo VPC de `aws-resources` é responsável pelo `fiap-rds-subnet-group`. Por isso, a policy `fiap-policy-platform-infra` permite consultar, criar, alterar, excluir e gerenciar tags somente desse subnet group. As instâncias e os clusters de banco continuam sob a role de Database. O escopo das ações por ARN de subnet group segue a [referência IAM do Amazon RDS](https://docs.aws.amazon.com/service-authorization/latest/reference/list_rds.html).

Se a execução falhar com `rds:DescribeDBSubnetGroups` negado para a role `fiap-role-github-actions-infra-infra`, atualizar o bootstrap com credenciais administrativas a partir do repositório Infra:

```powershell
terraform -chdir=infra/bootstrap init
terraform -chdir=infra/bootstrap plan -out=.terraform/bootstrap.tfplan
terraform -chdir=infra/bootstrap apply .terraform/bootstrap.tfplan
```

Revisar o plano antes de aplicar. Depois da atualização da policy, reexecutar os jobs com falha do workflow central. Publicar o código sem reaplicar o bootstrap não atualiza a policy existente na AWS. Preservar o state e os recursos já criados para que o Terraform retome a operação.

### Retomada após falha no node group e no EBS CSI

A role de infraestrutura tem `iam:GetRole` sobre o ARN exato `role/aws-service-role/eks-nodegroup.amazonaws.com/AWSServiceRoleForAmazonEKSNodegroup`. A permissão existente sobre `role/fiap-*` não cobre essa role vinculada ao serviço, que o EKS consulta ao criar o node group. A criação automática continua permitida por `iam:CreateServiceLinkedRole`, condicionada a `eks-nodegroup.amazonaws.com`; não é necessário criar a role manualmente. Ver [roles de serviço dos node groups](https://docs.aws.amazon.com/eks/latest/userguide/using-service-linked-roles-eks-nodegroups.html).

Se `CreateNodegroup` falhar por falta de `iam:GetRole`, reaplicar o bootstrap administrativo com os comandos acima. Publicar também a correção de `aws-resources/storage.tf`, que faz o EBS CSI aguardar o módulo EKS, incluindo os nós e o Pod Identity Agent. Depois, iniciar uma nova execução `apply` no workflow central para selecionar o novo SHA de infraestrutura. Reexecutar uma execução anterior conserva o SHA já resolvido e pode usar o código antigo.

O timeout do EBS CSI com estado `DEGRADED` pode ser consequência da ausência de nós. Se persistir após a criação do node group, consultar a causa específica antes de repetir o apply:

```powershell
aws eks describe-addon --cluster-name fiap-eks-cluster --addon-name aws-ebs-csi-driver --region us-east-1 --query 'addon.{status:status,issues:health.issues}'
```

Um add-on marcado como tainted pelo apply anterior pode ser recriado no próximo plano, conforme o aviso do provider. Revisar essa substituição; não remover recursos ou editar o state manualmente para contornar a falha.

## Estados e dependências

aws-resources → database (DB: RDS, segredos e TLS MongoDB) → kubernetes-addons → kubernetes-configs → messaging (Kafka/MongoDB) → inicialização/migrations/aplicações → api-gateway.

### External Secrets com InvalidProviderConfig

Se SecretStore ficar `Ready=False/InvalidProviderConfig`, os ExternalSecrets não criam os Secrets locais. No caso de `newrelic-license`, Collector e bundle ficam sem a licença e o Helm pode expirar. Em 07/11/2026, CloudTrail confirmou `AccessDenied` para `sts:TagSession` ao operador assumir todas as roles `fiap-eso-*`.

EKS Pod Identity adiciona [tags de sessão transitivas](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-abac.html). O encadeamento exige `sts:AssumeRole` e `sts:TagSession` tanto na policy do controller (`kubernetes-addons`) quanto na confiança das roles por namespace (`kubernetes-configs`). A permissão fica limitada às seis roles existentes; os ARNs de leitura dos segredos não mudam. O checksum das policies nas anotações dos SecretStores provoca nova reconciliação após atualizar o IAM.

Publicar a correção do Infra e iniciar **novo apply completo** no workflow central, para executar addons antes de configs. Reexecutar somente o job configs da execução antiga não atualiza a policy do controller. Essa correção não exige bootstrap administrativo. O Terraform continua aguardando a licença Ready antes de instalar o New Relic.

Os dois estágios executam testes Terraform de plano com providers simulados e estados fictícios antes do apply/destroy. Eles verificam a cadeia de confiança com tags, o escopo das seis roles, a leitura restrita dos segredos e os nomes DNS do bootstrap, sem criar recursos AWS.

No destroy, kubernetes-configs sai antes de database, que fornece os ARNs e a CA. Para recuperar uma execução que já apagou database, o runner passa `-var=destroy_mode=true` somente no plano `-destroy` de configurações; esse caminho deixa de consultar o state database. O apply força false e continua exigindo os outputs reais. Publicar Infra antes do principal e iniciar novo destroy para retomar, mantendo os states. Testes com providers simulados cobrem a leitura normal e a ausência dessa dependência na recuperação.

### Primeiro plano de messaging

`Plan: ... to add` pode ser um plano parcial seguido de erro; conferir também as mensagens anteriores ao resumo. A execução de 07/11/2026 falhou no plano de `kubernetes_manifest.kafka["statefulset.yaml"]`, com `unmarshaling unknown values is not supported`: interpolar random_id em templatefile e depois chamar yamldecode tornava o manifesto inteiro desconhecido antes do primeiro apply. A mensagem genérica de GroupVersionKind/CRD não indicava ausência de CRD para o StatefulSet nativo.

O recurso random_id.kafka é preservado no mesmo state. Seu valor é escrito pelo recurso nativo kubernetes_config_map_v1.kafka_cluster, e o StatefulSet estático referencia kafka-cluster/cluster-id por configMapKeyRef. Assim, tipo/nome do manifesto são conhecidos no primeiro plano, e o ID continua aleatório e estável durante a vida do volume. O teste messaging/tests/initial-plan.tftest.hcl executa um plano com ID ainda desconhecido; a pipeline executa esse teste antes de aplicar.

O script identifica as fases plan/apply/verificação e emite uma anotação com estágio, operação, fase, linha e código de saída em falha. A etapa de diagnóstico Kubernetes também atende messaging, coletando workloads, volumes e eventos de fiap-messaging/fiap-mongodb sem imprimir dados de Secrets. Os planos continuam temporários, sem publicação como artifacts. Para usar a correção, publicar Infra e iniciar novo apply central; não exige bootstrap ou descarte de state.

No apply, o Job controller adiciona `batch.kubernetes.io/controller-uid`, `batch.kubernetes.io/job-name` e as labels legadas ao Pod template de kafka-topics. O recurso kubernetes_manifest.kafka["topics.yaml"] declara `spec.template.metadata.labels` em computed_fields, preservando também os campos padrão metadata.labels/annotations. Essa configuração aceita as labels adicionadas pelo servidor; a label kafka-init usada pela NetworkPolicy continua declarada, e os outros manifestos mantêm somente os campos computados padrão. Ver [computed fields do provider](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest).

Após `Provider produced inconsistent result after apply`, a consulta somente de leitura ao state em 07/11/2026 confirmou o Job marcado como tainted. Publicar a correção do Infra e iniciar novo apply central permite ao Terraform substituir esse Job; os comandos de tópicos usam --if-not-exists. Revisar essa substituição no plano, preservando o state, o cluster-id e os volumes dos brokers. Não exige bootstrap nem exclusão manual. Os testes Terraform cobrem a exceção restrita ao Job e a preservação da label de rede; a aplicação real continua sendo validada no EKS.

MongoDB substitui DocumentDB e usa replica set rs0 de um membro com autenticação/TLS, Service interno e PVC gp3 criptografado de 20 GiB. A role ESO fiap-eso-mongodb acessa somente o segredo fiap-mongodb-admin criado pelo DB. Reaplicar o bootstrap administrativo antes do primeiro apply dessa versão para autorizar o novo segredo na role Database. Publicar Infra/DB/Execution antes de iniciar uma nova execução central; revisar a remoção do DocumentDB/segredo antigo no plano, sem descartar o state. Não há migração de dados; o destroy remove os PVCs/EBS MongoDB e Kafka antes de retirar EBS CSI.

O node group usa três `c7i-flex.large` x86_64, com 2 vCPUs e 4 GiB por nó. Esse tipo mantém a capacidade prevista originalmente com `t3.medium` e é [elegível ao Free Tier atual](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-free-tier-usage.html). A troca corrige `AsgInstanceLaunchFailures / InvalidParameterCombination` quando a conta restringe o lançamento aos tipos elegíveis. Não reduzir para instâncias micro/small: o Kafka solicita 1536 MiB em um único pod, além da memória necessária para sistema, agentes e demais aplicações.

Em 07/11/2026, consultas somente de leitura na conta do deploy confirmaram `FreeTierEligible=true`, 2 vCPUs, 4096 MiB e arquitetura x86_64 para `c7i-flex.large`, com oferta em `us-east-1a` e `us-east-1b`. Oferta não garante capacidade instantânea. Para conferir novamente:

```powershell
aws ec2 describe-instance-types --region us-east-1 --instance-types c7i-flex.large --query 'InstanceTypes[].{Type:InstanceType,FreeTier:FreeTierEligible,vCPU:VCpuInfo.DefaultVCpus,MemoryMiB:MemoryInfo.SizeInMiB}'
aws ec2 describe-instance-type-offerings --region us-east-1 --location-type availability-zone --filters Name=instance-type,Values=c7i-flex.large Name=location,Values=us-east-1a,us-east-1b
```

Publicar a alteração no Infra e iniciar uma nova execução `apply` do workflow central. Revisar a substituição do node group com falha no plano; manter state e recursos gerenciados pelo Terraform. Esta mudança de tipo não exige reaplicar o bootstrap de IAM. Elegibilidade EC2 não torna a plataforma inteira gratuita: créditos, prazo do plano e cobrança dos demais serviços devem ser acompanhados na conta.

O Terraform do gateway recebe internal_alb_listener_arn pela pipeline, guarda-o em output e não usa lookup obrigatório do ALB durante destroy. O plano fica no diretório temporário do runner e é aplicado no mesmo job, sem artifact de plano.

A geração de JWT/senhas é automática. Não fornecer jwt_signing_key/db_password/db_username como variables de Terraform. NEW_RELIC_LICENSE_KEY continua um secret externo de ingestão. Leitura de remote state expõe o state completo à role autorizada, inclusive valores sensíveis; isto não é um mecanismo de isolamento de segredos.
