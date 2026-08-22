# Infraestrutura AWS

Os estados Terraform são separados para reduzir o impacto das mudanças e devem ser executados na ordem das dependências.

## Componentes

| Diretório | Responsabilidade |
| --- | --- |
| `bootstrap` | Cria o bucket S3 do state, o provedor OIDC do GitHub e as IAM Roles das pipelines. |
| `aws-resources` | Cria VPC, EKS, repositórios ECR e o segredo JWT do backend. |
| `kubernetes-addons` | Instala External Secrets e Metrics Server no EKS. |
| `kubernetes-configs` | Cria namespaces, SecretStore e a stack de observabilidade. |

O PostgreSQL/RDS e seu segredo ficam no repositório [`fiap-tech-challenge-db`](https://github.com/Maieru/fiap-tech-challenge-db).

## Ordem de implantação

Na primeira implantação, intercale o estado do banco entre os estados deste repositório:

```text
bootstrap → aws-resources → database (repositório DB) → kubernetes-addons → kubernetes-configs
```

`kubernetes-addons` lê tanto o state de `aws-resources` quanto o state de `database`, pois a IAM Role do External Secrets precisa de acesso aos dois segredos.

## Pré-requisitos

- Terraform 1.13.x;
- AWS CLI v2 autenticada na conta;
- `kubectl` para validar o cluster;
- permissões para S3, IAM, VPC/EC2, EKS, ECR, Secrets Manager e recursos relacionados.

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

## GitHub Actions

Este repositório é responsável por executar seus próprios estados Terraform:

| Workflow | Responsabilidade |
| --- | --- |
| `apply-core-infrastructure.yml` | Aplica `bootstrap` e `aws-resources`. |
| `apply-kubernetes-infrastructure.yml` | Aplica `kubernetes-addons` e `kubernetes-configs`, depois que o banco existe. |
| `destroy-expensive-infrastructure.yml` | Destrói as configurações e add-ons do Kubernetes e desabilita o EKS. |
| `terraform-stage.yml` | Implementação reutilizável de plan, aprovação e apply. |

Todos podem ser chamados pelo orquestrador do repositório da aplicação; os três workflows de alto nível também podem ser iniciados manualmente neste repositório. Configure `INFRA_ACTION_ROLE` e `jwt_signing_key` nos repositórios que iniciarem os fluxos. O ARN da role é o output `github_actions_infra_role_arn["k8s_infra"]` do bootstrap.

Para repositórios privados, configure também `REPOSITORIES_TOKEN` com acesso de leitura. As configurações do GitHub Actions devem permitir que os workflows reutilizáveis sejam acessados pelos outros repositórios do projeto.

## Destruição

Respeite a ordem inversa:

```text
kubernetes-configs → kubernetes-addons → database (repositório DB) → aws-resources → bootstrap
```

Revise cuidadosamente os planos. A remoção do EKS e do banco pode interromper a aplicação, e o bucket do state usa `force_destroy`.
