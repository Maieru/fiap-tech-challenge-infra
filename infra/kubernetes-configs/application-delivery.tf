locals {
  application_delivery_namespaces = {
    os        = { namespace = "fiap-os", group = "fiap:deploy-os" }
    frontend  = { namespace = "fiap-frontend", group = "fiap:deploy-os" }
    execution = { namespace = "fiap-execution", group = "fiap:deploy-execution" }
    billing   = { namespace = "fiap-billing", group = "fiap:deploy-billing" }
  }
}

resource "kubernetes_role_v1" "application_delivery" {
  for_each = local.application_delivery_namespaces

  metadata {
    name      = "application-delivery"
    namespace = each.value.namespace
  }
  rule {
    api_groups = [""]
    resources  = ["configmaps", "services"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods", "pods/log", "events"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["replicasets"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["autoscaling"]
    resources  = ["horizontalpodautoscalers"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }
  rule {
    api_groups = ["external-secrets.io"]
    resources  = ["externalsecrets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }
  rule {
    api_groups     = ["external-secrets.io"]
    resources      = ["secretstores"]
    resource_names = ["aws-secrets-store"]
    verbs          = ["get"]
  }
  dynamic "rule" {
    for_each = each.key == "frontend" ? [true] : []
    content {
      api_groups = ["networking.k8s.io"]
      resources  = ["ingresses"]
      verbs      = ["get", "list", "watch", "create", "update", "patch"]
    }
  }
  rule {
    api_groups = ["batch"]
    resources  = ["jobs"]
    verbs      = ["get", "list", "watch", "create", "delete"]
  }
  depends_on = [kubernetes_namespace_v1.from_yaml]
}

resource "kubernetes_role_binding_v1" "application_delivery" {
  for_each = local.application_delivery_namespaces

  metadata {
    name      = "application-delivery"
    namespace = each.value.namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.application_delivery[each.key].metadata[0].name
  }
  subject {
    kind      = "Group"
    name      = each.value.group
    api_group = "rbac.authorization.k8s.io"
  }
}
