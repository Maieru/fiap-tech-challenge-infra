locals {
  kubernetes_namespace_files = setunion(
    fileset("${path.module}/../../k8s", "*/infra/namespace.yaml"),
    fileset("${path.module}/../../k8s", "*/infra/namespace.yml")
  )

  kubernetes_namespaces = {
    for manifest_file in local.kubernetes_namespace_files :
    manifest_file => yamldecode(file("${path.module}/../../k8s/${manifest_file}"))
  }

  kubernetes_secret_store_files = setunion(
    fileset("${path.module}/../../k8s", "*/infra/secret-store.yaml"),
    fileset("${path.module}/../../k8s", "*/infra/secret-store.yml")
  )

  kubernetes_secret_stores = {
    for manifest_file in local.kubernetes_secret_store_files :
    manifest_file => yamldecode(file("${path.module}/../../k8s/${manifest_file}"))
  }
}

resource "kubernetes_namespace_v1" "from_yaml" {
  for_each = local.kubernetes_namespaces

  metadata {
    name        = each.value.metadata.name
    labels      = try(each.value.metadata.labels, null)
    annotations = try(each.value.metadata.annotations, null)
  }
}

resource "kubernetes_manifest" "secret_store_from_yaml" {
  for_each = local.kubernetes_secret_stores

  manifest = merge(each.value, { spec = { provider = { aws = {
    service = "SecretsManager", region = var.aws_region
    role    = aws_iam_role.secret_store[split("/", each.key)[0]].arn
  } } } })

  depends_on = [
    kubernetes_namespace_v1.from_yaml,
    aws_iam_role_policy.secret_store
  ]
}
