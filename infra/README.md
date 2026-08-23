# Infraestrutura AWS

Os estados Terraform são separados para reduzir o impacto das mudanças e devem ser executados na ordem das dependências.

## Componentes

| Diretório | Responsabilidade |
| --- | --- |
| `bootstrap` | Cria o bucket S3 do state, o provedor OIDC do GitHub e as IAM Roles das pipelines. |
| `aws-resources` | Cria VPC, sub-redes privadas de aplicação, grupos de segurança, EKS, ECR e o segredo JWT. |
| `kubernetes-addons` | Instala External Secrets, Metrics Server e AWS Load Balancer Controller no EKS. |
| `kubernetes-configs` | Cria namespaces, SecretStore e a stack de observabilidade. |
| `api-gateway` | Cria HTTP API, VPC Link, stage, throttling e access logs após o ALB interno existir. |

O PostgreSQL/RDS e seu segredo ficam no repositório [`fiap-tech-challenge-db`](https://github.com/Maieru/fiap-tech-challenge-db).

## Ordem de implantação

Na primeira implantação, intercale o banco e o deploy das aplicações entre os estados deste repositório:

```text
bootstrap → aws-resources → database → kubernetes-addons → kubernetes-configs
→ deploy das aplicações e Ingresses → api-gateway
```

`kubernetes-addons` lê tanto o state de `aws-resources` quanto o state de `database`, pois a IAM Role do External Secrets precisa de acesso aos dois segredos.
O estado `api-gateway` só pode ser planejado depois que o AWS Load Balancer Controller criar o ALB `fiap-internal-edge`, pois a integração privada usa o ARN do listener desse balanceador.

## Pré-requisitos

- Terraform 1.13.x;
- AWS CLI v2 autenticada na conta;
- `kubectl` para validar o cluster;
- permissões para S3, IAM, VPC/EC2, EKS, ECR, ELB, API Gateway, CloudWatch Logs, Secrets Manager e recursos relacionados.

Todos os recursos usam `us-east-1` por padrão.

## Bootstrap inicial

Como o bucket do backend ainda não existe na primeira execução, crie-o inicialmente com state local e depois migre o state:

```powershell
terraform -chdir=infra/bootstrap init -backend=false
terraform -chdir=infra/bootstrap fmt -check
terraform -chdir=infra/bootstrap validate
terraform -chdir=infra/bootstrap plan -out=.terraform/tfplan
terraform -chdir=infra/bootstrap apply .terraform/tfplan
terraform -chdir=infra/bootstrap init -migrate-state
```

Nas execuções seguintes, use `terraform init` normalmente.

## Recursos AWS

Crie `infra/aws-resources/terraform.tfvars` sem versioná-lo:

```hcl
jwt_signing_key = "uma_chave_jwt_longa_e_aleatoria"
```

Execute o ciclo padrão:

```powershell
terraform -chdir=infra/aws-resources init
terraform -chdir=infra/aws-resources fmt -check
terraform -chdir=infra/aws-resources validate
terraform -chdir=infra/aws-resources plan -out=.terraform/tfplan
terraform -chdir=infra/aws-resources apply .terraform/tfplan
```

Depois aplique o estado `infra/database` do repositório de banco.

## Kubernetes

Com o banco criado e os nós do EKS em estado `Ready`, aplique:

```powershell
terraform -chdir=infra/kubernetes-addons init
terraform -chdir=infra/kubernetes-addons fmt -check
terraform -chdir=infra/kubernetes-addons validate
terraform -chdir=infra/kubernetes-addons plan -out=.terraform/tfplan
terraform -chdir=infra/kubernetes-addons apply .terraform/tfplan

terraform -chdir=infra/kubernetes-configs init
terraform -chdir=infra/kubernetes-configs fmt -check
terraform -chdir=infra/kubernetes-configs validate
terraform -chdir=infra/kubernetes-configs plan -out=.terraform/tfplan
terraform -chdir=infra/kubernetes-configs apply .terraform/tfplan
```

Os manifests e arquivos de observabilidade consumidos por `kubernetes-configs` estão versionados neste repositório em `k8s` e `src/ObservabilityConfig`.

## API Gateway

Depois de aplicar os manifests da aplicação e aguardar o endereço do Ingress, execute:

```powershell
terraform -chdir=infra/api-gateway init
terraform -chdir=infra/api-gateway fmt -check
terraform -chdir=infra/api-gateway validate
terraform -chdir=infra/api-gateway plan -out=.terraform/tfplan
terraform -chdir=infra/api-gateway apply .terraform/tfplan
```

O endpoint público encaminha todas as rotas pelo VPC Link ao ALB interno. O ALB envia `/api/*` ao backend e utiliza o frontend como destino das demais rotas. Os access logs não armazenam headers, corpos ou tokens e permanecem sete dias no CloudWatch Logs.

## GitHub Actions

Este repositório é responsável por executar seus próprios estados Terraform:

| Workflow | Responsabilidade |
| --- | --- |
| `apply-core-infrastructure.yml` | Aplica `bootstrap` e `aws-resources`. |
| `apply-kubernetes-infrastructure.yml` | Aplica `kubernetes-addons` e `kubernetes-configs`, depois que o banco existe. |
| `apply-edge-infrastructure.yml` | Aplica `api-gateway` depois que o deploy criar o ALB interno. |
| `destroy-kubernetes-infrastructure.yml` | Destrói API Gateway, Ingresses/ALB, `kubernetes-configs` e `kubernetes-addons`, mantendo o EKS disponível para a remoção do banco. |
| `destroy-expensive-infrastructure.yml` | Desabilita o EKS depois que os recursos Kubernetes e o banco de dados forem removidos pelo orquestrador. |
| `terraform-stage.yml` | Implementação reutilizável de plan, aprovação e apply. |

Todos podem ser chamados pelo orquestrador do repositório da aplicação; os workflows de alto nível também podem ser iniciados manualmente neste repositório. Configure `INFRA_ACTION_ROLE` e `jwt_signing_key` nos repositórios que iniciarem os fluxos. O ARN da role é o output `github_actions_infra_role_arn["k8s_infra"]` do bootstrap.

Para repositórios privados, configure também `REPOSITORIES_TOKEN` com acesso de leitura. As configurações do GitHub Actions devem permitir que os workflows reutilizáveis sejam acessados pelos outros repositórios do projeto.

## Destruição

Respeite a ordem inversa:

```text
api-gateway → Ingresses/ALB → kubernetes-configs → kubernetes-addons
→ database (repositório DB) → aws-resources → bootstrap
```

Revise cuidadosamente os planos. A remoção do EKS e do banco pode interromper a aplicação, e o bucket do state usa `force_destroy`.
