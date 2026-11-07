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

aws-resources → database (DB) → kubernetes-addons → kubernetes-configs → messaging → inicialização/migrations/aplicações → api-gateway.

O Terraform do gateway recebe internal_alb_listener_arn pela pipeline, guarda-o em output e não usa lookup obrigatório do ALB durante destroy. O plano fica no diretório temporário do runner e é aplicado no mesmo job, sem artifact de plano.

A geração de JWT/senhas é automática. Não fornecer jwt_signing_key/db_password/db_username como variables de Terraform. NEW_RELIC_LICENSE_KEY continua um secret externo de ingestão. Leitura de remote state expõe o state completo à role autorizada, inclusive valores sensíveis; isto não é um mecanismo de isolamento de segredos.
