resource "random_id" "kafka" { byte_length = 16 }
resource "kubernetes_namespace_v1" "messaging" {
  metadata { name = "fiap-messaging" }
}
resource "kubernetes_config_map_v1" "kafka_cluster" {
  metadata {
    name      = "kafka-cluster"
    namespace = "fiap-messaging"
  }
  data       = { "cluster-id" = substr(random_id.kafka.b64_url, 0, 22) }
  depends_on = [kubernetes_namespace_v1.messaging]
}
resource "kubernetes_storage_class_v1" "kafka" {
  metadata { name = "fiap-kafka-gp3" }
  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"
  parameters          = { type = "gp3", encrypted = "true", tagSpecification_1 = "Project=fiap-tech-challenge", tagSpecification_2 = "Component=kafka" }
}
resource "kubernetes_manifest" "kafka" {
  for_each   = fileset("${path.module}/../../k8s/messaging", "*.yaml")
  manifest   = yamldecode(file("${path.module}/../../k8s/messaging/${each.key}"))
  depends_on = [kubernetes_namespace_v1.messaging, kubernetes_storage_class_v1.kafka, kubernetes_config_map_v1.kafka_cluster]
}
output "bootstrap_servers" { value = "kafka.fiap-messaging.svc.cluster.local:9092" }
