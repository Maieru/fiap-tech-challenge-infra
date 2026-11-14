# Infraestrutura AWS dos microsserviços

Terraform provisiona VPC, EKS/ECR, IAM, EBS CSI, External Secrets, Kafka, MongoDB, observabilidade e API Gateway. RDS e os segredos/certificados dos bancos pertencem ao repositório DB; aplicações mantêm imagens, migrations e workloads.

A entrada operacional é **Manage AWS microservices platform**, no repositório principal. Ela chama os workflows reutilizáveis deste repositório, com commits explícitos e OIDC do chamador central. Não há execução manual avulsa de provisionamento.

Consulte o [guia dos estágios e bootstrap](infra/README.md) e o [guia operacional central](https://github.com/Maieru/fiap-tech-challenge/blob/main/docs/operacao/plataforma-aws.md). Antes da primeira ativação, conferir a compatibilidade dos estados e recursos com a topologia declarada. Estados incompatíveis exigem conciliação antes do apply.

## Pré-requisitos e estrutura

- Terraform 1.13.0, versão usada pelo CI, com providers dos lockfiles de cada estágio.
- Os exemplos usam PowerShell 7; Node.js 22+ e Bash para testes e scripts de plataforma; Docker para o ensaio MongoDB isolado.
- AWS CLI, kubectl e Helm para diagnóstico remoto. O ciclo GitHub instala suas ferramentas no runner e usa OIDC.
- Bootstrap administrativo aplicado e variables/secrets no repositório principal antes de ativar o laboratório.

infra contém os módulos Terraform; k8s contém recursos compartilhados; scripts/platform contém entrega, verificação e recuperação; src/ObservabilityConfig mantém Collector e valores Helm. Workloads das APIs pertencem aos repositórios dos serviços.

## Estágios ativos

| Estágio | Responsabilidade |
| --- | --- |
| bootstrap | Backend S3 protegido/versionado, OIDC e roles das pipelines; execução administrativa inicial |
| aws-resources | Rede, EKS/ECR, Pod Identity, EBS CSI, credencial JWT aleatória e access entries |
| kubernetes-addons | Controllers, metrics-server e licença New Relic |
| kubernetes-configs | Namespaces, RBAC, SecretStores/roles por namespace, CAs e observabilidade |
| messaging | Kafka KRaft e MongoDB replica set, PVCs gp3, Services internos, NetworkPolicies e tópicos |
| api-gateway | HTTPS público, VPC Link e integração com listener ALB recebido por input |

O diretório infra/serverless não é um estágio aceito pelo workflow dos microsserviços e não deve ser aplicado nesse ciclo.

A criação intercala database (DB), inicialização, publicação/deploy das aplicações e Ingresses. Destroy remove tudo em ordem inversa e preserva somente bootstrap/state/roles das pipelines. Dados, EBS e imagens ECR são descartáveis; não há snapshots finais dos bancos.

No Manage AWS, o destroy remove aplicações → messaging (MongoDB/Kafka e discos) → configurações → database (RDS e inventário dos dados) → add-ons → core. Configurações consome outputs database e deve ser destruído antes de esvaziá-los. Em messaging, o script ajusta reclaim dos PVs vinculados a PVCs dos namespaces `fiap-mongodb`/`fiap-messaging` para Delete, exclui PVCs restantes após o Terraform e aguarda a exclusão EBS. O estágio DB bloqueia a retirada dos controllers se ainda encontrar bancos ou discos do projeto. `terraform-destroy.test.mjs` exercita esse script com comandos simulados, incluindo falhas e rejeição de volume inválido, sem executar AWS.

Se database já foi destruído em uma execução interrompida, publicar Infra antes do principal e iniciar novo destroy. O runner usa `destroy_mode=true` somente no plano `-destroy` de kubernetes-configs; a recuperação remove a consulta ao state database já vazio. No apply, o runner força false e mantém os outputs obrigatórios. A remoção usa o plano salvo e os recursos registrados no state de configurações. Os testes Terraform verificam o caminho normal e a recuperação com providers simulados.

## Verificação local

Na raiz, os testes usam CLIs/inventário simulados e não aplicam recursos AWS:

```powershell
node --test scripts/platform/*.test.mjs
```

Para validar os mesmos seis estágios do CI sem inicializar o backend remoto:

```powershell
$previousTfDataDir = $env:TF_DATA_DIR
$validationRoot = Join-Path ([IO.Path]::GetTempPath()) ('fiap-infra-validate-' + [Guid]::NewGuid().ToString('N'))
try {
    foreach ($stage in @('bootstrap', 'aws-resources', 'kubernetes-addons', 'kubernetes-configs', 'messaging', 'api-gateway')) {
        $env:TF_DATA_DIR = Join-Path $validationRoot $stage
        terraform "-chdir=infra/$stage" fmt -check
        if ($LASTEXITCODE -ne 0) { throw "terraform fmt falhou em $stage" }
        terraform "-chdir=infra/$stage" init -backend=false -input=false
        if ($LASTEXITCODE -ne 0) { throw "terraform init falhou em $stage" }
        terraform "-chdir=infra/$stage" validate -no-color
        if ($LASTEXITCODE -ne 0) { throw "terraform validate falhou em $stage" }
    }
} finally {
    $env:TF_DATA_DIR = $previousTfDataDir
}
```

init baixa providers e exige acesso ao registry. validate não acessa o backend nem comprova IAM, conectividade ou compatibilidade AWS. Os testes Terraform com providers simulados ficam em infra/kubernetes-addons/tests, infra/kubernetes-configs/tests e infra/messaging/tests. O fluxo remoto executa preflight, gate de persistência e smoke; consulte o guia central para o ensaio completo.

## Credenciais Mercado Pago

O estágio `aws-resources` cria `fiap-billing-mercadopago-credentials` e expõe `mercado_pago_secret_arn`. O workflow reutilizável recebe `MERCADO_PAGO_ACCESS_TOKEN` e `MERCADO_PAGO_WEBHOOK_SECRET` do orquestrador principal e grava os valores via `scripts/platform/sync-mercado-pago-secret.mjs` após apply. Os valores não são variáveis nem recursos `secret_version` Terraform. A role OIDC de infraestrutura gerencia o segredo, e somente o SecretStore Billing recebe acesso de leitura. O bootstrap IAM precisa ser atualizado antes do primeiro apply com essa integração. O destroy inclui a espera de exclusão do novo segredo e não exige essas credenciais.

## Ativação, observabilidade e diagnóstico

O bootstrap inicial é administrativo e está descrito no [guia dos estágios](infra/README.md). No principal, configure as roles de Infra/Database e publicação/deploy por serviço, JWT_ISSUER/JWT_AUDIENCE e os secrets New Relic/Mercado Pago. Só então habilite PLATFORM_ENABLED=true e execute apply. O agendamento às 03:00 UTC usa destroy; dados e volumes do laboratório são descartados. A tabela completa de entradas fica no [guia central](https://github.com/Maieru/fiap-tech-challenge/blob/main/docs/operacao/plataforma-aws.md).

- [Recursos Kubernetes, CAs e isolamento](k8s/README.md).
- [Collector, New Relic e consultas](src/ObservabilityConfig/README.md).
- [Recuperação de IAM, node group, SecretStores e planos](infra/README.md).

Planos, estados e backups podem conter credenciais; não os publique como evidência. Falha de SecretStore, gate, readiness ou inventário exige corrigir a causa antes de avançar. Consultas de estado e eventos são diagnóstico; validação local não comprova deploy remoto.
