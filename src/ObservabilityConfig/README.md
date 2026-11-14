# Observabilidade com New Relic

OS, Execution e Billing exportam traces, métricas e logs por OTLP gRPC para o Collector compartilhado em 4317. O frontend envia traces/logs por OTLP HTTP via proxy /otlp em 4318. O Collector encaminha os sinais por OTLP/HTTPS ao New Relic; a integração Kubernetes coleta recursos do cluster separadamente.

| Componente | service.name |
| --- | --- |
| OS | oficina-os |
| Execution | oficina-execution |
| Billing | oficina-billing |
| Frontend | fiap-tech-challenge-frontend |

[otel-collector-config.yaml](otel-collector-config.yaml) define receivers, fila em memória, batch e exporter. [newrelic-kubernetes-values.yaml](newrelic-kubernetes-values.yaml) define os valores do chart de infraestrutura.

## Ambiente local

Requer Docker/Compose e acesso ao endpoint OTLP do New Relic. Na **raiz** de FiapTechChallengeFase1, preserve um .env existente ou copie .env.example em um checkout novo. Configure NEW_RELIC_LICENSE_KEY como chave de ingestão, não uma user API key. O endpoint padrão é https://otlp.nr-data.net; para conta EU, defina NEW_RELIC_OTLP_ENDPOINT=https://otlp.eu01.nr-data.net.

```powershell
docker compose -f compose.observability.yaml up -d
docker compose -f compose.observability.yaml ps
docker compose -f compose.observability.yaml logs -f otel-collector
```

A stack de negócio e a de observabilidade são projetos Compose separados. Somente o Collector exige licença; a aplicação pode iniciar sem ele. As portas 4317/4318 são publicadas em loopback. Para encerrar apenas o Collector:

```powershell
docker compose -f compose.observability.yaml down
```

### Habilitar os emissores

No Compose integrado atual, EXECUTION_ENABLE_OTLP=true habilita tanto OS quanto Execution, e OTEL_EXPORTER_OTLP_ENDPOINT pode apontar para http://host.docker.internal:4317. No Compose isolado OS, use OS_ENABLE_OTLP=true. Recrie os serviços para aplicar as variáveis.

Billing não recebe a opção de exportação pelo Compose principal. Para habilitá-la, salve uma configuração local complementar, por exemplo compose.telemetry.local.yaml na raiz do OS:

```yaml
services:
  billing-api:
    environment:
      Observability__EnableOtlp: "true"
      OTEL_EXPORTER_OTLP_ENDPOINT: http://host.docker.internal:4317
```

```powershell
docker compose -f compose.yaml -f compose.telemetry.local.yaml up -d --build
```

Se também usar pagamentos, combine o complemento descrito no [README principal](https://github.com/Maieru/fiap-tech-challenge#pagamentos-no-ambiente-local). Use os mesmos arquivos nas operações seguintes da stack.

host.docker.internal é fornecido pelo Docker Desktop. Em Docker nativo, configure um host-gateway ou endereço alcançável pelos containers. Para APIs no host, use Observability__EnableOtlp=true e OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317 no processo; dotnet run não carrega o .env do Compose.

O frontend usa /otlp na mesma origem: Vite aponta para localhost:4318 e Nginx recebe o endpoint HTTP de runtime. A licença fica somente no Collector, nunca em VITE_* ou no navegador. Páginas de link privado não inicializam telemetria, e seus tokens precisam continuar excluídos de logs, erros e URLs exportadas.

## Kubernetes e ciclo AWS

A entrada é manage-platform.yml do repositório principal. Os workflows de estágios do Infra são reutilizáveis, sem disparo manual independente. Configure NEW_RELIC_LICENSE_KEY como GitHub Secret do principal antes do apply:

1. kubernetes-addons cria fiap-newrelic-license com a chave license-key no Secrets Manager.
2. kubernetes-configs aplica SecretStore/ExternalSecret, ConfigMap e Collector no namespace fiap-observability.
3. O ExternalSecret newrelic-license precisa atingir Ready antes do Helm release newrelic-bundle.
4. As três APIs usam Observability__EnableOtlp=true nos ConfigMaps de produção e enviam a http://otel-collector.fiap-observability.svc:4317.

O Deployment do Collector é um template renderizado pelo Terraform, com checksum da configuração. Não aplique o YAML diretamente. A licença é uma variável Terraform sensível, mas fica no state/plano; restrinja o acesso. Os planos são temporários no runner. O segredo usa recovery_window_in_days=0; destroy não exige reenviar a licença de ingestão.

O endpoint remoto padrão é US. O módulo kubernetes-configs aceita new_relic_otlp_endpoint com os endpoints US/EU previstos em sua validação. A action central não expõe esse ajuste como input; para usar EU, ajuste a configuração do estágio/workflow de forma coordenada, sem supor que o .env local é lido pelo Terraform remoto.

### Rotação

Atualize NEW_RELIC_LICENSE_KEY no principal e execute novo apply. Aguarde sincronização do ExternalSecret e reinicie os workloads que leem a chave em variáveis: Collector e agentes do bundle. Atualizar o Secret não altera o ambiente de pods já iniciados. Não coloque a chave diretamente em valores Helm ou ConfigMaps.

## CPU e memória do Kubernetes

O módulo [newrelic.tf](../../infra/kubernetes-configs/newrelic.tf) fixa nri-bundle 8.0.22, namespace fiap-observability, timeout 600 segundos e rollback atomic. A licença vem do Secret newrelic-license; o nome do cluster vem do output EKS.

Os valores habilitam newrelic-infrastructure e kube-state-metrics, com lowDataMode=true. Logging adicional, injeção de agentes, Prometheus adicional, Pixie, coleta do control plane e eventos estão desabilitados. Metrics Server atende HPA/top e não substitui a integração New Relic. A coleta de infraestrutura vai diretamente ao provedor; os sinais da aplicação passam pelo Collector.

## Conferência após implantação

Com contexto Kubernetes correto e permissões de leitura:

```powershell
kubectl -n fiap-observability get secretstores,externalsecrets
kubectl -n fiap-observability wait --for=condition=Ready externalsecret/newrelic-license --timeout=180s
kubectl -n fiap-observability rollout status deployment/otel-collector --timeout=360s
kubectl -n fiap-observability get pods,deployments,daemonsets
helm status newrelic-bundle -n fiap-observability
kubectl -n fiap-observability logs deployment/otel-collector --tail=100
kubectl -n fiap-observability top pods
```

No Query Builder, procure dados recentes pelo service.name e pelo cluster correto:

```sql
FROM Span SELECT count(*) FACET service.name SINCE 30 minutes ago
FROM Log SELECT count(*) FACET service.name SINCE 30 minutes ago
FROM Metric SELECT uniques(metricName) WHERE service.name IN ('oficina-os', 'oficina-execution', 'oficina-billing') FACET service.name SINCE 30 minutes ago
FROM K8sNodeSample, K8sPodSample, K8sContainerSample SELECT count(*) FACET eventType(), clusterName SINCE 15 minutes ago
```

CPU por container, em millicores, e memória em MiB:

```sql
FROM K8sContainerSample SELECT average(cpuUsedCores) * 1000 AS 'CPU (mCPU)' WHERE clusterName = 'SEU_CLUSTER_EKS' AND namespaceName IN ('fiap-os', 'fiap-execution', 'fiap-billing', 'fiap-frontend') FACET namespaceName, podName, containerName SINCE 1 hour ago TIMESERIES 1 minute LIMIT MAX
FROM K8sContainerSample SELECT average(memoryWorkingSetBytes) / 1048576 AS 'Memória (MiB)' WHERE clusterName = 'SEU_CLUSTER_EKS' AND namespaceName IN ('fiap-os', 'fiap-execution', 'fiap-billing', 'fiap-frontend') FACET namespaceName, podName, containerName SINCE 1 hour ago TIMESERIES 1 minute LIMIT MAX
```

## Diagnóstico e limites

- 401/403 no exporter: confira chave de ingestão, região da conta e saída HTTPS 443.
- SecretStore InvalidProviderConfig ou ExternalSecret SecretSyncedError: confira Pod Identity e as permissões sts:AssumeRole/sts:TagSession do controller e das roles de namespace. Uma nova execução completa atualiza add-ons antes de configurações.
- Helm expirou: consulte Secret, eventos, scheduling, imagens e readiness; timeout isolado não identifica a causa. O fluxo executa scripts/platform/diagnose-kubernetes-configs.mjs em falha sem imprimir dados de Secrets.
- Pods Pending: confira capacidade dos nós e requests dos agentes, kube-state-metrics e aplicações. lowDataMode reduz volume de coleta, não garante espaço para agendar pods.
- 413: reveja tamanho dos registros e lotes. O Collector usa batch de até 256 registros, gzip e retentativas.
- Ausência de dados: confirme exportação habilitada no emissor, endpoint/protocolo, Collector e janela de consulta. Readiness da API não depende da ingestão no New Relic.

Filas em memória podem perder dados no restart. Não há endpoint /metrics para scraping nas APIs. Validação Terraform e renderização Helm não comprovam conectividade, ingestão, privacidade na borda ou disponibilidade remota.

- [Guia da plataforma](../../README.md).
- [Guia central de observabilidade](https://github.com/Maieru/fiap-tech-challenge/blob/main/docs/operacao/observabilidade.md).
- [Configuração oficial OTLP](https://docs.newrelic.com/docs/opentelemetry/best-practices/opentelemetry-otlp/).
