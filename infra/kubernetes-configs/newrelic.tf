resource "helm_release" "newrelic_kubernetes" {
  name       = "newrelic-bundle"
  repository = "https://helm-charts.newrelic.com"
  chart      = "nri-bundle"
  version    = "8.0.22"
  namespace  = "fiap-observability"
  wait       = true
  timeout    = 600
  atomic     = true

  values = [file("${local.observability_config_root}/newrelic-kubernetes-values.yaml")]

  set {
    name  = "global.cluster"
    value = data.terraform_remote_state.aws_resources.outputs.eks.name
    type  = "string"
  }

  # O ExternalSecret deve estar Ready antes de iniciar a instalacao do Helm.
  depends_on = [kubernetes_manifest.observability_application]
}
