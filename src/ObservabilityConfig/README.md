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

A configuração remota de laboratório está no repositório `FiapTechChallengeInfra`:

1. Configure o GitHub Actions secret `NEW_RELIC_LICENSE_KEY` com a chave de ingestão no repositório que dispara o workflow (`FiapTechChallengeFase1` para o orquestrador; `FiapTechChallengeInfra` para execução direta). Os workflows de aplicação e destruição repassam esse secret ao Terraform.
2. Aplique o estágio `infra/kubernetes-addons`. O Terraform cria o secret `fiap-newrelic-license` e sua versão com o JSON `{"license-key":"..."}` a partir da variável sensível e obrigatória `new_relic_license_key`. Para execução local, forneça `TF_VAR_new_relic_license_key` no ambiente antes de executar `terraform plan`/`apply` (também no `destroy`). Não é necessário cadastrar o valor manualmente no AWS Secrets Manager.
3. Se sua conta for EU, ajuste `NEW_RELIC_OTLP_ENDPOINT` em `k8s/observability/application/otel-collector-deployment.yaml` antes do deploy.
4. Aplique `infra/kubernetes-configs` e faça o deploy atualizado das aplicações. O ExternalSecret cria `newrelic-license` no namespace `fiap-observability`; o Collector lê a chave via `secretKeyRef`. Sem o valor no Secrets Manager, o Collector aguardará o Secret e não iniciará.
5. Verifique `kubectl -n fiap-observability get externalsecret newrelic-license` e `kubectl -n fiap-observability rollout status deployment/otel-collector`.

O workflow existente já aplica os estágios na ordem correta. O valor é gravado durante o estágio de add-ons, antes de configurar o Collector. A variável sensível oculta a chave na saída normal do Terraform, mas o valor fica armazenado no estado e no plano salvo (`tfplan`); restrinja o acesso ao backend e aos artifacts do workflow. O plano de `kubernetes-configs` remove os Deployments, Services e ConfigMaps antigos de Grafana, Prometheus, Loki e Jaeger. Se precisar do histórico ou de dashboards personalizados, exporte-os antes de aplicar: eles não são importados automaticamente pelo New Relic.

Para rotacionar a chave, atualize `NEW_RELIC_LICENSE_KEY` e reaplique `kubernetes-addons`; o Terraform cria uma nova versão do secret. Depois, aguarde a sincronização do ExternalSecret (até 1h) e execute `kubectl -n fiap-observability rollout restart deployment/otel-collector`, pois variáveis de ambiente não são atualizadas em pods existentes. O Terraform atual usa recovery_window_in_days = 0 para esse segredo, sem janela de recuperação configurada.

## Verificação no New Relic

Procure os serviços pelo nome na interface de entidades/APM e consulte no Query Builder:

```sql
FROM Span SELECT count(*) FACET service.name SINCE 30 minutes ago
FROM Log SELECT count(*) FACET service.name SINCE 30 minutes ago
FROM Metric SELECT uniques(metricName) WHERE service.name = 'fiap-tech-challenge-backend' SINCE 30 minutes ago
```

Para diagnóstico, use `docker compose logs otel-collector` ou `kubectl -n fiap-observability logs deployment/otel-collector`. Erros 401/403 indicam problema de chave/conta; confira também região e saída HTTPS na porta 443. O Collector usa lotes de até 256 registros, gzip, limite de memória e retentativas. A fila é em memória: reinícios podem perder dados pendentes. Se receber 413, reduza o lote ou o tamanho dos registros (o limite de ingestão é por bytes).

A API passa a exportar métricas exclusivamente por OTLP; o endpoint `/metrics` e o exporter Prometheus foram removidos. O Collector envia telemetria da aplicação. A coleta de CPU/memória e estado do Kubernetes é declarada separadamente pelo chart nri-bundle no estágio kubernetes-configs. Dashboards Grafana e recursos exclusivos do agente New Relic Browser não são migrados automaticamente.

Referência: [configuração oficial OTLP do New Relic](https://docs.newrelic.com/docs/opentelemetry/best-practices/opentelemetry-otlp/).


## CPU e memória do Kubernetes

O estágio `infra/kubernetes-configs` instala o Helm release `newrelic-bundle`, chart `nri-bundle` fixado em `8.0.22`, no namespace `fiap-observability`. Os valores estão em `newrelic-kubernetes-values.yaml`. O nome do cluster vem do output EKS do estágio `aws-resources`.

Componentes habilitados:

- DaemonSet `newrelic-bundle-nrk8s-kubelet`: coleta recursos de nós, pods e containers.
- Deployment `newrelic-bundle-kube-state-metrics`: expõe o estado dos objetos Kubernetes.
- Deployment `newrelic-bundle-nrk8s-ksm`: coleta esse estado e o envia ao New Relic.

A integração usa `newrelic-license`, campo `license-key`, criado pelo ExternalSecret existente. A chave não é passada como valor Helm. O Helm aguarda os workloads ficarem prontos por até 10 minutos, incluindo o tempo de sincronização do Secret. Falhas na instalação acionam rollback (`atomic`).

A telemetria do cluster é enviada diretamente pela integração ao New Relic. Traces, métricas e logs da aplicação continuam no Collector OTLP existente. Logging, injeção de agentes, Prometheus adicional, Pixie e eventos Kubernetes estão desabilitados neste bundle. O metrics-server existente continua atendendo o Kubernetes/HPA; ele não substitui kube-state-metrics.

A configuração atende aos managed node groups EC2 atuais. Não configura coleta dos componentes internos do control plane gerenciado do EKS nem suporte a Fargate. `global.lowDataMode=true` usa intervalo de 30 segundos na integração de infraestrutura. O chart cria RBAC de leitura e utiliza os acessos ao nó previstos pelo agente, incluindo container privilegiado. Os agentes precisam acessar o kubelet, a API Kubernetes e os endpoints HTTPS de ingestão do New Relic.

### Aplicação

Execute o workflow de infraestrutura existente, mantendo a ordem `aws-resources` → `kubernetes-addons` → `kubernetes-configs`. Para um ambiente já provisionado, reaplique `kubernetes-configs` com as mudanças. Não é necessário alterar o backend ou informar outra licença.

Execução local, a partir da raiz de `FiapTechChallengeInfra`, com credenciais AWS do ambiente:

```powershell
terraform -chdir=infra/kubernetes-configs init
terraform -chdir=infra/kubernetes-configs plan -out=tfplan
terraform -chdir=infra/kubernetes-configs apply tfplan
```

Revise o plano antes de aplicar, inclusive outras mudanças pendentes desse estágio. O lockfile inclui o provider Helm 2.17.0. Na destruição, a dependência Terraform remove o release antes dos manifests e do namespace que ele utiliza.

### Conferência após aplicação

```powershell
kubectl -n fiap-observability wait --for=condition=Ready externalsecret/newrelic-license --timeout=180s
helm status newrelic-bundle -n fiap-observability
kubectl -n fiap-observability rollout status daemonset/newrelic-bundle-nrk8s-kubelet --timeout=180s
kubectl -n fiap-observability rollout status deployment/newrelic-bundle-kube-state-metrics --timeout=180s
kubectl -n fiap-observability rollout status deployment/newrelic-bundle-nrk8s-ksm --timeout=180s
kubectl -n fiap-observability get pods -o wide
```

No New Relic, abra Kubernetes e procure o nome real do cluster EKS. Aguarde alguns minutos para a ingestão inicial. Para conferir a chegada:

```sql
FROM K8sNodeSample, K8sPodSample, K8sContainerSample
SELECT count(*) FACET eventType(), clusterName SINCE 15 minutes ago
```

As consultas abaixo usam `K8sContainerSample`, não `Metric`. Substitua `SEU_CLUSTER_EKS` pelo nome do cluster.

CPU por container (millicores; 1000 mCPU = 1 core):

```sql
FROM K8sContainerSample
SELECT average(cpuUsedCores) * 1000 AS 'CPU (mCPU)'
WHERE clusterName = 'SEU_CLUSTER_EKS'
  AND namespaceName IN ('fiap-backend', 'fiap-frontend')
FACET namespaceName, podName, containerName
SINCE 1 hour ago TIMESERIES 1 minute LIMIT MAX
```

Memória por container (working set em MiB):

```sql
FROM K8sContainerSample
SELECT average(memoryWorkingSetBytes) / 1048576 AS 'Memória (MiB)'
WHERE clusterName = 'SEU_CLUSTER_EKS'
  AND namespaceName IN ('fiap-backend', 'fiap-frontend')
FACET namespaceName, podName, containerName
SINCE 1 hour ago TIMESERIES 1 minute LIMIT MAX
```

Memória relativa ao limite configurado, para containers com limite:

```sql
FROM K8sContainerSample
SELECT average(memoryWorkingSetUtilization) AS 'Memória (% do limite)'
WHERE clusterName = 'SEU_CLUSTER_EKS' AND memoryLimitBytes > 0
  AND namespaceName IN ('fiap-backend', 'fiap-frontend')
FACET namespaceName, podName, containerName
SINCE 1 hour ago TIMESERIES 1 minute LIMIT MAX
```

Para visão de nós, pods e workloads, use também o Kubernetes Cluster Explorer fornecido pela integração.

Se os pods ficarem Pending, confira `kubectl describe pod` e a capacidade dos nós. Nos valores padrão do chart, o DaemonSet reserva aproximadamente 200m CPU e 300 MB de memória por nó (dois containers); o coletor KSM reserva outros 200m/300 MB no cluster, além do kube-state-metrics configurado com 50m/64Mi. Isso deve ser considerado nos nós t3.small atuais. O modo de menor volume reduz a frequência de envio, não essas reservas.

Na rotação da licença, após sincronizar o ExternalSecret, reinicie também `daemonset/newrelic-bundle-nrk8s-kubelet` e `deployment/newrelic-bundle-nrk8s-ksm`, além do Collector, pois a chave é carregada por variável de ambiente.

Validação local: `terraform validate`, `terraform fmt -check` e renderização `helm template` do chart fixado. Essa validação não comprova conectividade nem ingestão real; essas verificações dependem da aplicação no EKS.

Referências: [chart nri-bundle](https://github.com/newrelic/helm-charts/tree/master/charts/nri-bundle), [integração de infraestrutura](https://github.com/newrelic/nri-kubernetes/tree/main/charts/newrelic-infrastructure) e [dicionário das métricas](https://docs.newrelic.com/attribute-dictionary/).
