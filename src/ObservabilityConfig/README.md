# Observabilidade com New Relic

Backend (.NET) e frontend (browser via proxy Nginx `/otlp`) enviam telemetria ao OpenTelemetry Collector. O Collector exporta traces, métricas e logs por OTLP/HTTP com TLS para o New Relic. A instrumentação existente e os nomes `fiap-tech-challenge-backend` e `fiap-tech-challenge-frontend` são preservados; o frontend emite traces e logs, e o backend também emite métricas.

## Ambiente local

1. No repositório `FiapTechChallengeFase1`, na pasta `src`, copie `.env.example` para `.env`.
2. Preencha `NEW_RELIC_LICENSE_KEY` com uma chave de ingestão (license key) da sua conta. Não use uma user API key. O arquivo `.env` é ignorado pelo Git.
3. O endpoint padrão é US (`https://otlp.nr-data.net`). Para conta EU, use `https://otlp.eu01.nr-data.net` em `NEW_RELIC_OTLP_ENDPOINT`.
4. Execute `docker compose up -d --build --remove-orphans` na pasta `src`. A opção remove os contêineres da stack anterior deste projeto Compose, sem remover volumes do banco.
5. Abra o frontend em `http://localhost:5173` e faça chamadas à API. Aguarde ao menos um minuto para a exportação periódica de métricas.

A chave existe apenas no ambiente do Collector: nunca a coloque em variáveis `VITE_*` ou no navegador. O Compose exige uma chave não vazia para iniciar.

## Kubernetes / AWS

A configuração de produção está no repositório `FiapTechChallengeInfra`:

1. Aplique o estágio `infra/kubernetes-addons`. Ele cria o secret **sem valor** `fiap-newrelic-license` no AWS Secrets Manager e concede ao External Secrets acesso a esse ARN.
2. No AWS Secrets Manager, região `us-east-1`, cadastre o valor JSON `{"license-key":"SUA_CHAVE_DE_INGESTAO"}` nesse secret. O valor não é versionado nem gerenciado pelo Terraform.
3. Se sua conta for EU, ajuste `NEW_RELIC_OTLP_ENDPOINT` em `k8s/observability/application/otel-collector-deployment.yaml` antes do deploy.
4. Aplique `infra/kubernetes-configs` e faça o deploy atualizado das aplicações. O ExternalSecret cria `newrelic-license` no namespace `fiap-observability`; o Collector lê a chave via `secretKeyRef`. Sem o valor no Secrets Manager, o Collector aguardará o Secret e não iniciará.
5. Verifique `kubectl -n fiap-observability get externalsecret newrelic-license` e `kubectl -n fiap-observability rollout status deployment/otel-collector`.

O workflow existente já aplica os estágios na ordem correta. Na primeira migração, cadastre o valor assim que o estágio de add-ons criar o secret. O plano de `kubernetes-configs` remove os Deployments, Services e ConfigMaps antigos de Grafana, Prometheus, Loki e Jaeger. Se precisar do histórico ou de dashboards personalizados, exporte-os antes de aplicar: eles não são importados automaticamente pelo New Relic.

Após rotação da chave, aguarde a sincronização do ExternalSecret (até 1h) e execute `kubectl -n fiap-observability rollout restart deployment/otel-collector`, pois variáveis de ambiente não são atualizadas em pods existentes. O secret AWS possui janela de recuperação de 7 dias; ao destruir e recriar a infraestrutura nesse intervalo, restaure/importe o secret ou aguarde sua exclusão antes de recriá-lo.

## Verificação no New Relic

Procure os serviços pelo nome na interface de entidades/APM e consulte no Query Builder:

```sql
FROM Span SELECT count(*) FACET service.name SINCE 30 minutes ago
FROM Log SELECT count(*) FACET service.name SINCE 30 minutes ago
FROM Metric SELECT uniques(metricName) WHERE service.name = 'fiap-tech-challenge-backend' SINCE 30 minutes ago
```

Para diagnóstico, use `docker compose logs otel-collector` ou `kubectl -n fiap-observability logs deployment/otel-collector`. Erros 401/403 indicam problema de chave/conta; confira também região e saída HTTPS na porta 443. O Collector usa lotes de até 256 registros, gzip, limite de memória e retentativas. A fila é em memória: reinícios podem perder dados pendentes. Se receber 413, reduza o lote ou o tamanho dos registros (o limite de ingestão é por bytes).

A API passa a exportar métricas exclusivamente por OTLP; o endpoint `/metrics` e o exporter Prometheus foram removidos. Esta integração envia a telemetria de aplicação existente; dashboards Grafana, monitoramento de nós Kubernetes e recursos exclusivos do agente New Relic Browser não são migrados automaticamente.

Referência: [configuração oficial OTLP do New Relic](https://docs.newrelic.com/docs/opentelemetry/best-practices/opentelemetry-otlp/).
