mock_provider "random" {}
mock_provider "kubernetes" {}

override_data {
  target = data.terraform_remote_state.aws_resources
  values = { outputs = {
    eks = { name = "fiap-eks-cluster", endpoint = "https://eks.invalid", ca = "dGVzdA==" }
  } }
}

run "initial_manifests_are_known_before_random_cluster_id_exists" {
  command = plan
  assert {
    condition = (
      kubernetes_manifest.kafka["statefulset.yaml"].manifest.apiVersion == "apps/v1" &&
      kubernetes_manifest.kafka["statefulset.yaml"].manifest.kind == "StatefulSet"
    )
    error_message = "GVK do StatefulSet deve ser conhecido no primeiro plano, sem ID aleatorio criado."
  }
  assert {
    condition = alltrue([for manifest in kubernetes_manifest.kafka :
      length(manifest.manifest.metadata.name) > 0 && length(manifest.manifest.kind) > 0
    ])
    error_message = "Todos os manifestos Kafka devem ser decodificaveis no primeiro plano."
  }
  assert {
    condition = one([
      for environment in kubernetes_manifest.kafka["statefulset.yaml"].manifest.spec.template.spec.containers[0].env :
      environment.valueFrom.configMapKeyRef if environment.name == "CLUSTER_ID"
    ]) == { name = "kafka-cluster", key = "cluster-id" }
    error_message = "O broker deve receber a identidade persistida por referencia ao ConfigMap."
  }
  assert {
    condition     = kubernetes_config_map_v1.kafka_cluster.metadata[0].name == "kafka-cluster"
    error_message = "O ConfigMap deve corresponder a referencia do StatefulSet."
  }
}
