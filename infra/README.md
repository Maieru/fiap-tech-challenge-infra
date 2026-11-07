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

## Estados e dependências

aws-resources → database (DB) → kubernetes-addons → kubernetes-configs → messaging → inicialização/migrations/aplicações → api-gateway.

O Terraform do gateway recebe internal_alb_listener_arn pela pipeline, guarda-o em output e não usa lookup obrigatório do ALB durante destroy. O plano fica no diretório temporário do runner e é aplicado no mesmo job, sem artifact de plano.

A geração de JWT/senhas é automática. Não fornecer jwt_signing_key/db_password/db_username como variables de Terraform. NEW_RELIC_LICENSE_KEY continua um secret externo de ingestão. Leitura de remote state expõe o state completo à role autorizada, inclusive valores sensíveis; isto não é um mecanismo de isolamento de segredos.
