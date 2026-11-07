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

  observability_config_checksum = sha256(file("${local.observability_config_root}/otel-collector-config.yaml"))
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

resource "kubernetes_manifest" "observability_application" {
  for_each = local.observability_manifests

  manifest = each.value

  depends_on = [
    kubernetes_namespace_v1.from_yaml,
    kubernetes_config_map_v1.otel_collector,
    kubernetes_manifest.secret_store_from_yaml
  ]
}
