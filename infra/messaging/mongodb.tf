resource "kubernetes_storage_class_v1" "mongodb" {
  metadata { name = "fiap-mongodb-gp3" }
  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"
  parameters          = { type = "gp3", encrypted = "true", tagSpecification_1 = "Project=fiap-tech-challenge", tagSpecification_2 = "Component=mongodb" }
}
resource "kubernetes_config_map_v1" "mongodb_scripts" {
  metadata {
    name      = "mongodb-scripts"
    namespace = "fiap-mongodb"
  }
  data = { for name in fileset("${path.module}/../../k8s/mongodb/scripts", "*") : name => file("${path.module}/../../k8s/mongodb/scripts/${name}") }
}
resource "kubernetes_manifest" "mongodb" {
  for_each = fileset("${path.module}/../../k8s/mongodb", "*.yaml")
  manifest = yamldecode(templatefile("${path.module}/../../k8s/mongodb/${each.key}", {
    scripts_checksum = sha256(jsonencode(kubernetes_config_map_v1.mongodb_scripts.data))
  }))
  depends_on = [kubernetes_storage_class_v1.mongodb, kubernetes_config_map_v1.mongodb_scripts]
}
