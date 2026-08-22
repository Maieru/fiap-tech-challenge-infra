locals {
  observability_config_root   = "${path.module}/../../src/ObservabilityConfig"
  observability_manifest_root = "${path.module}/../../k8s/observability/application"

  observability_manifest_files = fileset(local.observability_manifest_root, "*.yaml")
  observability_manifests = {
    for manifest_file in local.observability_manifest_files :
    manifest_file => yamldecode(templatefile("${local.observability_manifest_root}/${manifest_file}", {
      observability_config_checksum = local.observability_config_checksum
    }))
  }

  grafana_dashboard_files = fileset("${local.observability_config_root}/grafana/dashboards", "*.json")
  grafana_dashboards = {
    for dashboard_file in local.grafana_dashboard_files :
    dashboard_file => file("${local.observability_config_root}/grafana/dashboards/${dashboard_file}")
  }

  observability_config_checksum = sha256(join("", concat(
    [
      file("${local.observability_config_root}/otel-collector-config.yaml"),
      file("${local.observability_config_root}/prometheus.yml"),
      file("${local.observability_config_root}/grafana/provisioning/datasources/prometheus.yaml"),
      file("${local.observability_config_root}/grafana/provisioning/datasources/loki.yaml"),
      file("${local.observability_config_root}/grafana/provisioning/dashboards/dashboards.yaml")
    ],
    values(local.grafana_dashboards)
  )))
}

resource "kubernetes_config_map_v1" "otel_collector" {
  metadata {
    name      = "otel-collector-config"
    namespace = "fiap-observability"
  }

  data = {
    "config.yaml" = file("${local.observability_config_root}/otel-collector-config.yaml")
  }

  depends_on = [kubernetes_namespace_v1.from_yaml]
}

resource "kubernetes_config_map_v1" "prometheus" {
  metadata {
    name      = "prometheus-config"
    namespace = "fiap-observability"
  }

  data = {
    "prometheus.yml" = replace(
      file("${local.observability_config_root}/prometheus.yml"),
      "fiap.techchallenge.fase1.api:8080",
      "fiap-backend-service.fiap-backend.svc.cluster.local:8080"
    )
  }

  depends_on = [kubernetes_namespace_v1.from_yaml]
}

resource "kubernetes_config_map_v1" "grafana_datasources" {
  metadata {
    name      = "grafana-datasources"
    namespace = "fiap-observability"
  }

  data = {
    "prometheus.yaml" = file("${local.observability_config_root}/grafana/provisioning/datasources/prometheus.yaml")
    "loki.yaml"       = file("${local.observability_config_root}/grafana/provisioning/datasources/loki.yaml")
  }

  depends_on = [kubernetes_namespace_v1.from_yaml]
}

resource "kubernetes_config_map_v1" "grafana_dashboard_provider" {
  metadata {
    name      = "grafana-dashboard-provider"
    namespace = "fiap-observability"
  }

  data = {
    "dashboards.yaml" = file("${local.observability_config_root}/grafana/provisioning/dashboards/dashboards.yaml")
  }

  depends_on = [kubernetes_namespace_v1.from_yaml]
}

resource "kubernetes_config_map_v1" "grafana_dashboards" {
  metadata {
    name      = "grafana-dashboards"
    namespace = "fiap-observability"
  }

  data = local.grafana_dashboards

  depends_on = [kubernetes_namespace_v1.from_yaml]
}

resource "kubernetes_manifest" "observability_application" {
  for_each = local.observability_manifests

  manifest = each.value

  depends_on = [
    kubernetes_namespace_v1.from_yaml,
    kubernetes_config_map_v1.otel_collector,
    kubernetes_config_map_v1.prometheus,
    kubernetes_config_map_v1.grafana_datasources,
    kubernetes_config_map_v1.grafana_dashboard_provider,
    kubernetes_config_map_v1.grafana_dashboards
  ]
}
