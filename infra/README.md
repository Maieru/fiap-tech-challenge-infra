# Estágios Terraform e bootstrap

A operação diária usa manage-platform.yml do principal. terraform-stage.yml, cleanup-applications.yml, verify-runtime.yml e verify-destroy.yml são workflows reutilizáveis que aceitam o chamador Maieru/fiap-tech-challenge em main. O workflow validate.yml também pode ser disparado manualmente e não aplica recursos.

A região padrão é us-east-1 e o CI fixa Terraform 1.13.0. [README principal](../README.md) contém pré-requisitos e validação sem backend; o [guia central](https://github.com/Maieru/fiap-tech-challenge/blob/main/docs/operacao/plataforma-aws.md) contém a tabela de variables/secrets e o ciclo completo.

## Mapa dos estágios

| Diretório | Responsabilidade | Dependências principais |
| --- | --- | --- |
| bootstrap | S3 de estado, OIDC e roles das pipelines | Conta e credenciais administrativas |
| aws-resources | Rede, EKS/ECR, IAM de aplicações, storage e JWT | Bootstrap |
| kubernetes-addons | Controllers, Metrics Server e licença New Relic | Cluster e credenciais de ingestão |
| kubernetes-configs | Namespaces, RBAC, SecretStores, CAs e observabilidade | Cluster, add-ons e outputs DB |
| messaging | Kafka e MongoDB no EKS, PVCs, Services, NetworkPolicies e tópicos | Configurações, CAs, segredos e storage |
| api-gateway | Entrada HTTPS e integração VPC Link/ALB | Listener ALB das aplicações |

O estágio database pertence ao repositório DB e entra entre aws-resources e add-ons. A inicialização de usuários/gate de persistência ocorre depois de messaging; a entrega aplica migrations, APIs e frontend antes do gateway. infra/serverless não é estágio aceito pelo ciclo dos microsserviços.

## Bootstrap administrativo

O bootstrap é executado por um administrador e fica fora de apply/destroy cotidianos. Os nomes de bucket, estados e roles estão declarados no código; alterações exigem coordenação com os backends e consumidores de remote state.

### Backend já existente

Na raiz do Infra, com credenciais administrativas da conta correta:

```powershell
aws sts get-caller-identity
terraform -chdir=infra/bootstrap init
terraform -chdir=infra/bootstrap plan -out=.terraform/bootstrap.tfplan
```

Revise o plano, especialmente exclusões de roles com dependentes. Depois aplique exatamente o plano revisado:

```powershell
terraform -chdir=infra/bootstrap apply .terraform/bootstrap.tfplan
```

Os outputs github_actions_infra_role_arn e application_delivery_role_arns alimentam as Variables do principal. Use as roles corretas de Infra/Database e de publicação/deploy por aplicação, não uma role administrativa para todos os jobs.

### Conta sem backend S3

Em um checkout exclusivo para bootstrap:

1. Renomeie temporariamente infra/bootstrap/backend.tf para backend.tf.disabled.
2. Execute init e gere/aplique um plano com credenciais administrativas, usando state local.
3. Restaure backend.tf e execute terraform -chdir=infra/bootstrap init -migrate-state para mover o state ao bucket criado.
4. Proteja backups e cópias do state local, que podem conter dados sensíveis. Verifique a migração antes de removê-los.

O bucket tem prevent_destroy, force_destroy=false, criptografia, bloqueio público e versionamento. O ciclo cotidiano preserva o prefixo bootstrap, backend e roles das pipelines. Não crie um segundo state para recursos que já possuem gestão ativa.

## Estados, planos e destruição

Cada estágio tem backend e chave próprios. Outputs são consumidos por terraform_remote_state; essa permissão permite ler o state completo e não isola segredos.

A pipeline confere o SHA de origem, executa fmt/validate e testes de plano com providers simulados nos estágios aplicáveis. O plano fica em RUNNER_TEMP e é aplicado no mesmo job, sem publicar artifact de plano. A saída Plan pode ser parcial e seguida de erro; confira a fase/linha anotada e o resultado final.

Destroy remove gateway/aplicações antes das dependências, messaging e volumes antes do driver, configurações antes de database e, depois, add-ons/core. Se database já estiver ausente, o runner usa destroy_mode=true somente no plano -destroy de configurações; no apply, força false e exige outputs reais. Não descarte state para contornar falhas.

JWT, senhas e TLS dos bancos são gerados pelo Terraform/DB. Não configure jwt_signing_key, db_username ou db_password como entradas das pipelines. Licença New Relic e credenciais Mercado Pago são entradas externas com fluxos próprios de segredo.

## Recuperação e diagnóstico

### DB Subnet Group com AccessDenied

aws-resources cria fiap-rds-subnet-group pelo módulo VPC. A policy de Infra precisa das ações RDS correspondentes sobre esse subnet group, separadas das permissões Database para instâncias. Se a role não tiver a policy atual, reaplique bootstrap com plano revisado; publicar o arquivo Terraform sozinho não altera IAM remoto. Depois retome o ciclo sem apagar o state.

### Node group ou EBS CSI indisponível

A role Infra precisa consultar a service-linked role AWSServiceRoleForAmazonEKSNodegroup; permissões somente sobre role/fiap-* não a cobrem. O EBS CSI espera o módulo EKS, nós e Pod Identity Agent. Um add-on DEGRADED pode ser consequência de ausência de nós; consulte a causa antes de repetir:

```powershell
aws eks describe-addon --cluster-name fiap-eks-cluster --addon-name aws-ebs-csi-driver --region us-east-1 --query 'addon.{status:status,issues:health.issues}'
```

O node group configura três c7i-flex.large x86_64. Confira capacidade/oferta e elegibilidade da conta diretamente na AWS; nenhum tipo de instância torna toda a plataforma gratuita. Kafka exige memória para um único pod, além de sistema, agentes e aplicações. Não reduza capacidade sem rever requests e scheduling.

### SecretStore InvalidProviderConfig

Confira a cadeia Pod Identity → controller ESO → role do namespace, incluindo sts:AssumeRole e sts:TagSession em policy e trust. As leituras devem continuar restritas aos ARNs necessários. Os testes em kubernetes-addons/tests e kubernetes-configs/tests verificam os escopos com providers simulados.

Uma nova execução completa aplica add-ons antes de configurações e provoca reconciliação via checksum IAM. Reexecutar apenas um job conserva os SHAs da execução original. Configurações aguarda a licença Ready antes do Helm; timeout sozinho não distingue IAM, Secret, imagem, readiness ou scheduling.

### Primeiro plano e Job de tópicos

O ID Kafka é random_id.kafka no state e vai para o ConfigMap kafka-cluster. O StatefulSet estático referencia a chave por configMapKeyRef, permitindo um primeiro plano com ID ainda desconhecido. Não regenere o cluster-id mantendo um volume formatado.

O controller adiciona labels ao Pod template do Job kafka-topics. computed_fields aceita esse campo e preserva a label kafka-init da NetworkPolicy. O teste messaging/tests/initial-plan.tftest.hcl cobre essas condições. Um Job tainted pode exigir substituição planejada; os tópicos usam --if-not-exists, mas a troca precisa ser revisada no plano.

### MongoDB e volumes

DB cria credenciais, CA e certificados; messaging cria MongoDB rs0 autenticado com TLS e PVC gp3 criptografado. O gate DB usa a imagem Execution para conferir persistência antes do rollout. A API recebe só sua conexão e CA pública.

No destroy, o script identifica PVs dos namespaces fiap-mongodb/fiap-messaging, ajusta reclaim para Delete, remove PVCs restantes e aguarda a exclusão EBS antes dos controllers. O inventário DB bloqueia a sequência se bancos/discos do projeto permanecerem ou se falhar a consulta AWS.

### Gateway e retomada de fontes

O gateway recebe internal_alb_listener_arn pela pipeline e o preserva em output para destroy, evitando lookup obrigatório do ALB já removido. Se publicar uma correção de Infra, inicie nova execução central para selecionar o novo SHA; repetir jobs antigos reutiliza o código selecionado naquela execução.

## Verificação e evidências

[Validação local](../README.md#verificação-local) executa testes de scripts e fmt/init sem backend/validate em dados temporários. Em falha de estágio Kubernetes, diagnose-kubernetes-configs.mjs consulta workloads, volumes, eventos e capacidade sem imprimir dados de Secrets. A execução remota precisa comprovar readiness, smoke, telemetria e inventário final; validação estática não é evidência de deploy.
